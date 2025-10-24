/// PrivilegedHelper mediates between the GUI and the privileged helper by owning XPC client state,
/// staging selected image/device metadata, and emitting component events in response to helper replies.
/// Inbound: component events from the UI and XPC reply dictionaries; Outbound: XPC requests to the helper
/// (write ISO, query version) plus UI events for progress/errors. No direct disk I/O occurs here beyond
/// validating identifiers and retaining ISO/device selections for the helper.
// ----------------------------------------------------------------------------------------------------
const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");
const env = @import("../../env.zig");
const AppConfig = @import("../../config.zig");

const freetracer_lib = @import("freetracer-lib");
const c = freetracer_lib.c;
const Debug = freetracer_lib.Debug;
const StorageDevice = freetracer_lib.types.StorageDevice;
const isLinux = freetracer_lib.types.isLinux;
const isMacOS = freetracer_lib.types.isMacOS;
const Device = freetracer_lib.device;
const Character = freetracer_lib.constants.Character;
const String = freetracer_lib.String;

const DeviceType = freetracer_lib.types.DeviceType;
const ImageType = freetracer_lib.types.ImageType;

const xpc = freetracer_lib.xpc;
const XPCService = freetracer_lib.Mach.XPCService;
const XPCConnection = freetracer_lib.Mach.XPCConnection;
const XPCObject = freetracer_lib.Mach.XPCObject;
const HelperRequestCode = freetracer_lib.constants.HelperRequestCode;
const HelperResponseCode = freetracer_lib.constants.HelperResponseCode;
const HelperInstallCode = freetracer_lib.constants.HelperInstallCode;

const ISOFilePicker = @import("../FilePicker/FilePicker.zig");
const PrivilegedHelperTool = @import("../../modules/macos/PrivilegedHelperTool.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const AppManager = @import("../../managers/AppManager.zig");
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
const PrivilegedHelperState = struct {
    isActive: bool = false,
    isHelperInstalled: bool = false,
    installedVersion: [:0]const u8 = "-1",
    isoPath: ?[:0]const u8 = null,
    targetDisk: ?[:0]const u8 = null,
    device: ?StorageDevice = null,
    imageType: ImageType = undefined,
};

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(PrivilegedHelperState);
const ComponentWorker = ComponentFramework.Worker(PrivilegedHelperState);
const ComponentEvent = ComponentFramework.Event;
const ComponentName = EventManager.ComponentName.PRIVILEGED_HELPER;
const EventResult = ComponentFramework.EventResult;

const DataFlasherUI = @import("../DataFlasher/DataFlasherUI.zig");

const PrivilegedHelper = @This();

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
xpcClient: XPCService,
isHelperInstalled: bool = false,
reinstallAttempts: u8 = 0,
checkedDiskPermissions: bool = false,
needsDiskPermissions: bool = false,

pub const Events = struct {
    //
    pub const onWriteISOToDeviceRequest = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_write_iso_to_device"),
        struct {
            isoPath: [:0]const u8,
            imageType: ImageType,
            targetDisk: [:0]const u8,
            device: StorageDevice,
        },
        struct {},
    );

    pub const onHelperToolConfirmedSuccessfulComms = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_successful_comms_confirmed"),
        struct {},
        struct {},
    );

    pub const onHelperVersionReceived = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_version_received"),
        struct { shouldHelperUpdate: bool },
        struct {},
    );

    pub const onDiskUnmountConfirmed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_disk_unmount_confirmed"),
        struct {},
        struct {},
    );

    pub const onHelperNeedsDiskPermissions = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_needs_disk_permissions"),
        struct {},
        struct {},
    );

    pub const onHelperISOFileOpenFailed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_iso_file_open_failed"),
        struct {},
        struct {},
    );

    pub const onHelperISOFileOpenSuccess = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_iso_file_open_success"),
        struct {},
        struct {},
    );

    pub const onHelperDeviceOpenFailed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_device_open_failed"),
        struct {},
        struct {},
    );

    pub const onHelperDeviceOpenSuccess = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_device_open_success"),
        struct {},
        struct {},
    );

    pub const onHelperWriteFailed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_write_failed"),
        struct {},
        struct {},
    );

    pub const onHelperWriteSuccess = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_write_success"),
        struct {},
        struct {},
    );

    pub const onISOWriteProgressChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_iso_write_progress_changed"),
        struct { newProgress: u64, rate: u64, rate_avg: u64, bytes_written: u64, bytes_total: u64 },
        struct {},
    );

    pub const onWriteVerificationProgressChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_write_verification_progress_changed"),
        struct { newProgress: u64 },
        struct {},
    );

    pub const onHelperVerificationFailed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_verification_failed"),
        struct {},
        struct {},
    );

    pub const onHelperVerificationSuccess = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_helper_verification_success"),
        struct {},
        struct {},
    );
};

pub fn init(allocator: std.mem.Allocator) !PrivilegedHelper {
    return PrivilegedHelper{
        .allocator = allocator,
        .state = ComponentState.init(PrivilegedHelperState{
            .isActive = false,
            // Set installed flag to true by default on Linux systems
            .isHelperInstalled = isLinux,
        }),
        .xpcClient = try XPCService.init(.{
            .isServer = false,
            .serviceName = "Freetracer XPC Client",
            .serverBundleId = @ptrCast(env.HELPER_BUNDLE_ID),
            .clientBundleId = @ptrCast(env.BUNDLE_ID),
            .requestHandler = @ptrCast(&PrivilegedHelper.messageHandler),
        }),
    };
}

pub fn initComponent(self: *PrivilegedHelper, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

pub fn initWorker(self: *PrivilegedHelper) !void {
    if (self.worker != null) return error.ComponentWorkerAlreadyInitialized;

    self.worker = ComponentWorker.init(
        self.allocator,
        &self.state,
        .{
            .run_fn = PrivilegedHelper.workerRun,
            .run_context = self,
            .callback_fn = PrivilegedHelper.workerCallback,
            .callback_context = self,
        },
        .{
            .onSameThreadAsCaller = false,
        },
    );
}

pub fn start(self: *PrivilegedHelper) !void {
    if (isLinux) return;

    try self.initWorker();

    // Verify if the Helper Tool is installed and set self.isHelperInstalled flag accordingly
    self.dispatchComponentAction();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "PrivilegedHelper: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).empty;

        Debug.log(.DEBUG, "PrivilegedHelper: finished initializing children.", .{});
    }
}

pub fn update(self: *PrivilegedHelper) !void {
    if (isLinux) return;

    self.checkAndJoinWorker();

    if (self.needsDiskPermissions) {
        self.xpcClient.timer.reset();
        return;
    }

    if (self.xpcClient.timer.isTimerSet and self.reinstallAttempts < 1) {
        if (std.time.timestamp() - self.xpcClient.timer.timeOfLastRequest > 3) {
            Debug.log(.ERROR, "Failed to communicate with Freetracer Helper Tool...", .{});
            defer self.xpcClient.timer.reset();

            const shouldReinstallHelper = osd.message(
                "Hmmm. It seems that Freetracer Helper Tool is not responding to Freetracer. Attempt reinstalling it?",
                .{ .level = .warning, .buttons = .ok_cancel },
            );

            if (!shouldReinstallHelper) {
                // TODO: quit app gracefully
                Debug.log(.ERROR, "User did not consent to reinstall. Aborting...", .{});
                return;
            }

            Debug.log(.ERROR, "User agreed to reinstall. Making reinstall attempt...", .{});

            const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
            waitForHelperToolInstall();
            self.reinstallAttempts += 1;

            if (installResult == HelperInstallCode.SUCCESS) {
                Debug.log(.INFO, "Freetracer Helper Tool is successfully installed!", .{});

                self.reinitializeXPCConnection() catch |err| {
                    Debug.log(.ERROR, "Failed to reinitialize XPC connection after daemon reinstall: {any}", .{err});
                    return error.FailedToReinitializeXPCConnection;
                };

                self.dispatchComponentAction();
            } else return error.FailedToInstallPrivilegedHelperTool;
        }
    } else if (self.xpcClient.timer.isTimerSet and self.reinstallAttempts >= 1) {
        // TODO: quit app gracefully
        _ = osd.message("Unfortunately, Freetracer still fails to communicate with the Freetracer Helper Tool. Unable to proceed at this stage -- apologies. Please submit a bug report at github.com/obx0/freetracer", .{ .level = .err, .buttons = .ok });
    }
}

pub fn draw(self: *PrivilegedHelper) !void {
    const isHelperToolInstalled = if (isMacOS) self.isHelperInstalled else if (isLinux) true else unreachable;

    rl.drawCircleV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, if (isHelperToolInstalled) .green else .red);
    rl.drawCircleLinesV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, .white);
}

pub fn handleEvent(self: *PrivilegedHelper, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    if (isLinux) return eventResult;

    eventLoop: switch (event.hash) {
        //
        Events.onWriteISOToDeviceRequest.Hash => {
            const data = Events.onWriteISOToDeviceRequest.getData(event) orelse break :eventLoop;

            try self.acquireStateDataOwnership(data.isoPath, data.targetDisk, data.device, data.imageType);

            self.installHelperIfNotInstalled() catch |err| {
                Debug.log(.ERROR, "An error occurred while trying to install Freetracer Helper Tool. Exiting event loop... {any}", .{err});
                break :eventLoop;
            };

            self.xpcClient.start();
            eventResult.validate(.SUCCESS);
        },

        Events.onHelperToolConfirmedSuccessfulComms.Hash => {
            self.xpcClient.timer.reset();
            const request: XPCObject = XPCService.createRequest(.GET_HELPER_VERSION);
            defer XPCService.releaseObject(request);
            XPCService.connectionSendMessage(self.xpcClient.service, request);
            eventResult.validate(.SUCCESS);
        },

        // TODO: Count internally number of attempts to avoid being stuck in an inifinite loop here
        Events.onHelperVersionReceived.Hash => {
            self.xpcClient.timer.reset();

            const eventData = Events.onHelperVersionReceived.getData(event) orelse break :eventLoop;

            if (eventData.shouldHelperUpdate) {
                const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();

                if (installResult != HelperInstallCode.SUCCESS) {
                    Debug.log(.ERROR, "Unable to update Freetracer Helper Tool... Aborting.", .{});
                    return error.UnableToUpdateHelperTool;
                }

                self.reinitializeXPCConnection() catch |err| {
                    Debug.log(.ERROR, "Failed to reinitialize XPC connection after daemon update: {any}", .{err});
                    return error.FailedToReinitializeXPCConnection;
                };

                self.dispatchComponentAction();
                break :eventLoop;
            }

            self.state.lock();
            errdefer self.state.unlock();

            if (self.state.data.targetDisk == null or self.state.data.isoPath == null) {
                Debug.log(.ERROR, "PrivilegedHelper Component's state value of targetDisk or isoPath is NULL when it should not be. Aborting...", .{});
                break :eventLoop;
            }

            const targetDisk: [:0]const u8 = self.state.data.targetDisk.?;
            const isoPath: [:0]const u8 = self.state.data.isoPath.?;
            const deviceServiceId: c_uint = self.state.data.device.?.serviceId;
            const deviceType: DeviceType = self.state.data.device.?.type;
            const imageType: ImageType = self.state.data.imageType;
            // const imageType: ImageType = EventManager.signal("iso_file_picker", )

            Debug.log(.INFO, "Sending deviceServiceId: {d}", .{deviceServiceId});

            Debug.log(.INFO, "targetDisk local set to the state value of: {s}", .{self.state.data.targetDisk.?});
            self.state.unlock();

            Debug.log(.INFO, "Sending target disk: {s}", .{targetDisk});

            self.requestWrite(targetDisk, isoPath, deviceServiceId, deviceType, imageType);

            eventResult.validate(.SUCCESS);
        },

        Events.onDiskUnmountConfirmed.Hash => {
            self.xpcClient.timer.reset();
            eventResult.validate(.SUCCESS);
        },

        Events.onHelperNeedsDiskPermissions.Hash => {
            self.xpcClient.timer.reset();
            Debug.log(.INFO, "Helper tool requires disk access permissions, alerting user.", .{});
            self.needsDiskPermissions = true;
            c.dispatch_async_f(c.dispatch_get_main_queue(), null, displayNeedPermissionsDialog);
        },

        else => {},
    }

    return eventResult;
}

/// TODO: Remove.
/// Deprecated and unnecessary. Full Disk Access is no longer neccessary since v0.9
fn displayNeedPermissionsDialog(context: ?*anyopaque) callconv(.c) void {
    _ = context;

    EventManager.broadcast(Events.onHelperDeviceOpenFailed.create(null, null));

    // TODO: Remove. Deprecated, no longer need full disk access.
    const result = osd.message("Writing to the device failed. MacOS' security policy requires 'Full Disk Access' for an app to write directly to a drive.\n\nFreetracer will only use this to write your selected ISO file to the selected device. Your other data will not be accessed.\n\nTo grant access:\n\nOpen System Settings > Privacy & Security > Full Disk Access.\nClick the (+) button and add Freetracer from the /Applications folder and relaunch Freetracer.", .{ .level = .warning, .buttons = .ok_cancel });

    if (result) freetracer_lib.MacOSPermissions.openPrivacySettings();
}

pub fn deinit(self: *PrivilegedHelper) void {
    self.cleanupComponentState();
}

pub fn reinitializeXPCConnection(self: *PrivilegedHelper) !void {
    Debug.log(.INFO, "Reinitializing XPC connection after daemon update...", .{});

    self.xpcClient.deinit();

    self.xpcClient = try XPCService.init(.{
        .isServer = false,
        .serviceName = "Freetracer XPC Client",
        .serverBundleId = @ptrCast(env.HELPER_BUNDLE_ID),
        .clientBundleId = @ptrCast(env.BUNDLE_ID),
        .requestHandler = @ptrCast(&PrivilegedHelper.messageHandler),
    });

    self.xpcClient.start();

    Debug.log(.INFO, "XPC connection successfully reinitialized and started.", .{});
}

pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;
}

pub fn dispatchComponentAction(self: *PrivilegedHelper) void {
    //
    const installCheckResult: HelperInstallCode = PrivilegedHelperTool.isHelperToolInstalled();

    self.state.lock();
    defer self.state.unlock();

    if (installCheckResult == HelperInstallCode.SUCCESS) {
        self.isHelperInstalled = true;
    } else self.isHelperInstalled = false;
}

pub fn checkAndJoinWorker(self: *PrivilegedHelper) void {
    if (self.worker) |*worker| {
        if (worker.status == ComponentFramework.WorkerStatus.NEEDS_JOINING) {
            Debug.log(.DEBUG, "PrivilegedHelper: Worker finished, needs joining...", .{});
            worker.join();
            Debug.log(.DEBUG, "PrivilegedHelper: Worker joined.", .{});
        }
    }
}

pub fn messageHandler(connection: xpc.xpc_connection_t, message: xpc.xpc_object_t) callconv(.c) void {
    Debug.log(.INFO, "CLIENT: Message Handler executed!", .{});

    const reply_type = xpc.xpc_get_type(message);

    if (reply_type == xpc.XPC_TYPE_DICTIONARY) {
        processResponseMessage(@ptrCast(connection), message) catch |err| {
            Debug.log(.ERROR, "Freetracer caught error processing a response from helper, error: {any}", .{err});
            return;
        };
    }
}

fn processResponseMessage(connection: XPCConnection, data: XPCObject) !void {
    const response: HelperResponseCode = try XPCService.parseResponse(data);

    Debug.log(.INFO, "Successfully received Helper response: {any}", .{response});

    switch (response) {
        .INITIAL_PONG => {
            Debug.log(.INFO, "Successfully established connection to Freetracer Helper Tool.", .{});
            EventManager.broadcast(Events.onHelperToolConfirmedSuccessfulComms.create(null, null));
        },

        .HELPER_VERSION_OBTAINED => {
            Debug.log(.INFO, "Should helper update: {any}", .{shouldHelperUpdate(data)});
            EventManager.broadcast(Events.onHelperVersionReceived.create(
                null,
                &Events.onHelperVersionReceived.Data{ .shouldHelperUpdate = shouldHelperUpdate(data) },
            ));
        },

        .DISK_UNMOUNT_SUCCESS => {
            Debug.log(.INFO, "Received a successful unmount response from the helper!", .{});
            EventManager.broadcast(Events.onDiskUnmountConfirmed.create(null, null));
        },

        .DISK_UNMOUNT_FAIL => {
            Debug.log(.ERROR, "Helper communicated that it failed to unmount requested disk.", .{});
            EventManager.broadcast(Events.onHelperDeviceOpenFailed.create(null, null));
        },

        .ISO_FILE_VALID => {
            Debug.log(.INFO, "Helper reported that the ISO file provided is valid.", .{});
            EventManager.broadcast(Events.onHelperISOFileOpenSuccess.create(null, null));
        },

        .ISO_FILE_INVALID => {
            Debug.log(.ERROR, "Helper reported that the ISO file is INVALID.", .{});
            EventManager.broadcast(Events.onHelperISOFileOpenFailed.create(null, null));
        },

        .DEVICE_VALID => {
            Debug.log(.ERROR, "Helper reported that the device is valid and opened.", .{});
            EventManager.broadcast(Events.onHelperDeviceOpenSuccess.create(null, null));
        },

        .DEVICE_INVALID => {
            Debug.log(.ERROR, "Helper reported that the selected device is INVALID.", .{});
            EventManager.broadcast(Events.onHelperDeviceOpenFailed.create(null, null));
        },

        .NEED_DISK_PERMISSIONS => {
            EventManager.broadcast(Events.onHelperNeedsDiskPermissions.create(null, null));
        },

        .ISO_WRITE_PROGRESS => {
            const progress = try XPCService.getUInt64(data, "write_progress");
            const speed = try XPCService.getUInt64(data, "write_rate");
            const speed_avg = try XPCService.getUInt64(data, "write_rate_avg");
            const bytes_written = try XPCService.getUInt64(data, "write_bytes");
            const bytes_total = try XPCService.getUInt64(data, "write_total_size");
            EventManager.broadcast(Events.onISOWriteProgressChanged.create(
                null,
                &Events.onISOWriteProgressChanged.Data{
                    .newProgress = progress,
                    .rate = speed,
                    .rate_avg = speed_avg,
                    .bytes_total = bytes_total,
                    .bytes_written = bytes_written,
                },
            ));
            // Debug.log(.INFO, "Write progress is: {d}", .{progress});
        },

        .ISO_WRITE_SUCCESS => {
            Debug.log(.INFO, "Helper reported that it has successfully written the ISO file to device.", .{});
            EventManager.broadcast(Events.onHelperWriteSuccess.create(null, null));
        },

        .ISO_WRITE_FAIL => {
            Debug.log(.ERROR, "Helper reported that it failed to write the ISO file.", .{});
            EventManager.broadcast(Events.onHelperWriteFailed.create(null, null));
        },

        .WRITE_VERIFICATION_PROGRESS => {
            const progress = try XPCService.getUInt64(data, "verification_progress");
            EventManager.broadcast(Events.onWriteVerificationProgressChanged.create(
                null,
                &Events.onWriteVerificationProgressChanged.Data{ .newProgress = progress },
            ));
            // Debug.log(.INFO, "Verification progress is: {d}", .{progress});
        },

        .WRITE_VERIFICATION_SUCCESS => {
            Debug.log(.INFO, "Helper successfully verified the ISO bytes written to device.", .{});
            EventManager.broadcast(Events.onHelperVerificationSuccess.create(null, null));
        },

        .WRITE_VERIFICATION_FAIL => {
            Debug.log(.ERROR, "Helper failed to verify bytes written to device.", .{});
            EventManager.broadcast(Events.onHelperVerificationFailed.create(null, null));
        },
    }

    _ = connection;
}

fn shouldHelperUpdate(dict: XPCObject) bool {
    const version = XPCService.parseString(dict, "version") catch |err| {
        Debug.log(.ERROR, "Freetracer couldn't parse Helper version received from the Helper. Error: {any}", .{err});
        return true;
    };

    Debug.log(.INFO, "Helper reported version is: {s}", .{version});
    return !std.mem.eql(u8, version, AppConfig.PRIVILEGED_TOOL_LATEST_VERSION);
}

fn waitForHelperToolInstall() void {
    Debug.log(.INFO, "Waiting to allow Helper Tool be registered with system launch daemon", .{});
    std.Thread.sleep(1_000_000_000);
}

/// Ensures the BSD disk identifier we forward to the helper is well-formed and references a removable disk alias.
/// Returns error.Invalid* on malformed strings; caller should abort the request before touching the helper.
fn validateDeviceIdentifier(identifier: [:0]const u8) !void {
    if (identifier.len == 0) return error.EmptyIdentifier;
    if (identifier.len > 31) return error.IdentifierTooLong;

    const valid_prefixes = [_][]const u8{ "disk", "rdisk" };
    var has_valid_prefix = false;
    for (valid_prefixes) |prefix| {
        if (std.mem.startsWith(u8, identifier, prefix)) {
            has_valid_prefix = true;
            break;
        }
    }
    if (!has_valid_prefix) return error.InvalidPrefix;

    for (identifier) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            return error.InvalidCharacter;
        }
    }
}

fn installHelperIfNotInstalled(self: *PrivilegedHelper) !void {
    if (!self.isHelperInstalled) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        waitForHelperToolInstall();

        if (installResult == HelperInstallCode.SUCCESS) {
            Debug.log(.INFO, "Fretracer Helper Tool is successfully installed!", .{});
            self.dispatchComponentAction();
        } else return error.FailedToInstallPrivilegedHelperTool;
    } else Debug.log(.INFO, "Determined that Freetracer Helper Tool is already installed.", .{});
}

/// Precondition: isoPath/targetDisk originate from trusted UI selection; this function performs final validation before XPC.
/// Posts the WRITE_ISO_TO_DEVICE request and leaves ownership of state data with `self.state` for helper callbacks.
fn requestWrite(self: *PrivilegedHelper, targetDisk: [:0]const u8, isoPath: [:0]const u8, deviceServiceId: c_uint, deviceType: DeviceType, imageType: ImageType) void {
    // Install or update the Privileged Helper Tool before sending unmount request

    Debug.log(.DEBUG, "requestWrite() received targetDisk: {s}", .{targetDisk});

    if (isoPath.len == 0) {
        Debug.log(.ERROR, "PrivilegedHelper.requestWrite(): empty isoPath provided. Aborting...", .{});
        return;
    }

    if (targetDisk.len < 2) {
        Debug.log(.ERROR, "PrivilegedHelper.requestWrite(): malformed targetDisk ('{any}') Aborting...", .{targetDisk});
        return;
    }

    // TODO: outsource this to a common lib function which does sanitization and other sanity checks

    validateDeviceIdentifier(targetDisk) catch |err| {
        Debug.log(.ERROR, "PrivilegedHelper.requestWrite(): invalid targetDisk '{s}'. Err: {any}", .{ targetDisk, err });
        return;
    };

    const deviceDir = "/dev/";

    var devicePathBuf: [std.fs.max_name_bytes]u8 = std.mem.zeroes([std.fs.max_name_bytes]u8);

    const devicePath = String.concatStrings(std.fs.max_name_bytes, &devicePathBuf, deviceDir, @ptrCast(targetDisk)) catch |err| {
        Debug.log(.ERROR, "Error while concatenating devicePath from directory and target disk. Err: {any}", .{err});
        return;
    };

    // NOTE: Critical and important permissions call
    requestMacOSInteractivePermissionDialog(devicePath);

    const request = XPCService.createRequest(.WRITE_ISO_TO_DEVICE);
    defer XPCService.releaseObject(request);
    XPCService.createString(request, "disk", targetDisk);
    XPCService.createString(request, "isoPath", isoPath);
    XPCService.createUInt64(request, "deviceServiceId", deviceServiceId);
    XPCService.createUInt64(request, "deviceType", @intFromEnum(deviceType));
    XPCService.createUInt64(request, "imageType", @intFromEnum(imageType));
    XPCService.connectionSendMessage(self.xpcClient.service, request);
}

/// Critical function, whose C open syscall gets intercepted by MacOS to present
/// and interactive dialog prompt to grant permission to Removable Volumes under
/// `Settings -> Privacy & Security -> Files & Folders -> Freetracer -> Removable Volumes`
/// Whether or not this returns an error is irrelevant (most likely will), the purpose
/// is to serve the permissions dialog and once allowed by user, the permission is
/// inherited by the privileged helper process.
fn requestMacOSInteractivePermissionDialog(devicePath: [:0]u8) void {
    const fd: c_int = c.open(@ptrCast(devicePath), c.O_RDWR, @as(c_uint, 0o644));
    _ = c.close(fd);
}

/// Copies the UI-provided ISO and disk identifiers into component-owned storage; caller must hold no state lock.
/// On failure previous state is cleared and ownership remains unchanged, preventing partial updates.
fn acquireStateDataOwnership(self: *PrivilegedHelper, isoPath: [:0]const u8, targetDisk: [:0]const u8, device: StorageDevice, imageType: ImageType) !void {
    self.cleanupComponentState();
    self.state.lock();
    defer self.state.unlock();
    const iso_copy = try self.allocator.dupeZ(u8, isoPath);
    errdefer self.allocator.free(iso_copy);
    const disk_copy = try self.allocator.dupeZ(u8, targetDisk);
    errdefer self.allocator.free(disk_copy);
    self.state.data.isoPath = iso_copy;
    self.state.data.targetDisk = disk_copy;
    self.state.data.device = device;
    self.state.data.imageType = imageType;
    Debug.log(.INFO, "Set to state: \n\tISO Path: {s}\n\ttargetDisk: {s}", .{ self.state.data.isoPath.?, self.state.data.targetDisk.? });
}

/// Releases any retained ISO/device selections and resets state so future operations start from a clean slate.
fn cleanupComponentState(self: *PrivilegedHelper) void {
    self.state.lock();
    defer self.state.unlock();

    if (self.state.data.isoPath) |path| {
        self.allocator.free(path);
        self.state.data.isoPath = null;
    }
    if (self.state.data.targetDisk) |disk| {
        self.allocator.free(disk);
        self.state.data.targetDisk = null;
    }

    self.state.data.device = null;
    self.state.data.imageType = undefined;
}

const ComponentImplementation = ComponentFramework.ImplementComponent(PrivilegedHelper);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
