const std = @import("std");
const rl = @import("raylib");
const env = @import("../../env.zig");
const AppConfig = @import("../../config.zig");

const freetracer_lib = @import("freetracer-lib");
const c = freetracer_lib.c;
const Debug = freetracer_lib.Debug;

const MachCommunicator = freetracer_lib.MachCommunicator;
const SerializedData = freetracer_lib.SerializedData;
const MachPortPacketSize = freetracer_lib.k.MachPortPacketSize;

const xpc = freetracer_lib.xpc;
const XPCService = freetracer_lib.XPCService;
const XPCConnection = freetracer_lib.XPCConnection;
const XPCObject = freetracer_lib.XPCObject;
const HelperRequestCode = freetracer_lib.HelperRequestCode;
const HelperResponseCode = freetracer_lib.HelperResponseCode;

const PrivilegedHelperTool = @import("../../modules/macos/PrivilegedHelperTool.zig");

const PrivilegedHelperState = struct {
    isActive: bool = false,
    isHelperInstalled: bool = false,
    installedVersion: [:0]const u8 = "-1",
    isoPath: ?[:0]const u8 = null,
    targetDisk: ?[:0]const u8 = null,
};

const System = @import("../../lib/sys/system.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(PrivilegedHelperState);
const ComponentWorker = ComponentFramework.Worker(PrivilegedHelperState);
const ComponentEvent = ComponentFramework.Event;
const ComponentName = EventManager.ComponentName.PRIVILEGED_HELPER;
const EventResult = ComponentFramework.EventResult;

const PrivilegedHelper = @This();

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
xpcClient: XPCService,
isHelperInstalled: bool = false,

pub const Events = struct {
    //
    pub const onWriteISOToDeviceRequest = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_write_iso_to_device"),
        struct {
            isoPath: [:0]const u8,
            targetDisk: [:0]const u8,
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
};

pub fn init(allocator: std.mem.Allocator) !PrivilegedHelper {
    return PrivilegedHelper{
        .allocator = allocator,
        .state = ComponentState.init(PrivilegedHelperState{
            .isActive = false,
            // Set installed flag to true by default on Linux systems
            .isHelperInstalled = System.isLinux,
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
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
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
    if (System.isLinux) return;

    try self.initWorker();

    // Verify if the Helper Tool is installed and set self.isHelperInstalled flag accordingly
    self.dispatchComponentAction();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "PrivilegedHelper: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        Debug.log(.DEBUG, "PrivilegedHelper: finished initializing children.", .{});
    }
}

pub fn update(self: *PrivilegedHelper) !void {
    if (System.isLinux) return;

    self.checkAndJoinWorker();
}

pub fn draw(self: *PrivilegedHelper) !void {
    const isHelperToolInstalled = if (System.isMac) self.isHelperInstalled else if (System.isLinux) true else unreachable;

    rl.drawCircleV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, if (isHelperToolInstalled) .green else .red);
    rl.drawCircleLinesV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, .white);
}

pub fn handleEvent(self: *PrivilegedHelper, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    if (System.isLinux) return eventResult;

    eventLoop: switch (event.hash) {
        //
        Events.onHelperToolConfirmedSuccessfulComms.Hash => {
            const request: XPCObject = XPCService.createRequest(.GET_HELPER_VERSION);
            defer XPCService.releaseObject(request);
            XPCService.connectionSendMessage(self.xpcClient.service, request);
            eventResult.validate(.SUCCESS);
        },

        // TODO: Count internally number of attempts to avoid being stuck in an inifinite loop here
        Events.onHelperVersionReceived.Hash => {
            const eventData = Events.onHelperVersionReceived.getData(event) orelse break :eventLoop;

            if (eventData.shouldHelperUpdate) {
                const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();

                if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) {
                    Debug.log(.ERROR, "Unable to update Freetracer Helper Tool... Aborting.", .{});
                    return error.UnableToUpdateHelperTool;
                }

                self.dispatchComponentAction();
                XPCService.pingServer(self.xpcClient.service);
                break :eventLoop;
            }

            self.state.lock();
            errdefer self.state.unlock();

            if (self.state.data.targetDisk == null) {
                Debug.log(.ERROR, "PrivilegedHelper Component's state value of targetDisk is NULL when it should not be. Aborting...", .{});
                break :eventLoop;
            }

            const targetDisk: [:0]const u8 = self.state.data.targetDisk.?;
            Debug.log(.INFO, "targetDisk local set to the state value of: {s}", .{self.state.data.targetDisk.?});
            self.state.unlock();

            Debug.log(.INFO, "Sending target disk: {s}", .{targetDisk});

            self.requestUnmount(targetDisk);
        },

        Events.onDiskUnmountConfirmed.Hash => {},

        Events.onWriteISOToDeviceRequest.Hash => {
            const data = Events.onWriteISOToDeviceRequest.getData(event) orelse break :eventLoop;

            try self.acquireStateDataOwnership(data.isoPath, data.targetDisk);

            self.installHelperIfNotInstalled() catch |err| {
                Debug.log(.ERROR, "An error occurred while trying to install Freetracer Helper Tool. Exiting event loop... {any}", .{err});
                break :eventLoop;
            };

            self.xpcClient.start();

            if (true) break :eventLoop;

            var unmountResponse: freetracer_lib.HelperUnmountRequestCode = self.requestUnmount(data.targetDisk);

            if (true) break :eventLoop;

            Debug.log(.INFO, "PrivilegedHelper Component first unmount request result: {any}", .{unmountResponse});

            if (unmountResponse == freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN) {
                Debug.log(.INFO, "PrivilegedHelper received a try again code, trying again...: {any}", .{unmountResponse});
                unmountResponse = self.requestUnmount(data.targetDisk);
            }

            Debug.log(.INFO, "PrivilegedHelper Component result of second unmount request: {any}", .{unmountResponse});

            if (unmountResponse != freetracer_lib.HelperUnmountRequestCode.SUCCESS) {
                Debug.log(.WARNING, "PrivilegedHelper.handleEvent(): interrupting event processing due to error response.", .{});
                break :eventLoop;
            }

            var diskPath = try self.allocator.alloc(u8, AppConfig.DISK_PREFIX.len + data.targetDisk.len);
            defer self.allocator.free(diskPath);

            @memcpy(diskPath[0..AppConfig.DISK_PREFIX.len], AppConfig.DISK_PREFIX);
            @memcpy(diskPath[AppConfig.DISK_PREFIX.len..], data.targetDisk);

            var finalDataString = try self.allocator.allocSentinel(u8, diskPath.len + data.isoPath.len + 1, 0x00);
            defer self.allocator.free(finalDataString);

            @memcpy(finalDataString[0..data.isoPath.len], data.isoPath);
            finalDataString[data.isoPath.len] = 0x3b; // semi-colon separator
            @memcpy(finalDataString[(data.isoPath.len + 1)..], diskPath);

            const writeResponse = requestWrite(@ptrCast(finalDataString));

            if (writeResponse == freetracer_lib.HelperReturnCode.SUCCESS) eventResult.validate(.SUCCESS);
        },

        else => {},
    }

    return eventResult;
}

pub fn deinit(self: *PrivilegedHelper) void {
    //
    self.cleanupComponentState();
}

pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;

    // xpc.dispatch_main();
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;
}

pub fn dispatchComponentAction(self: *PrivilegedHelper) void {
    //
    const installCheckResult: freetracer_lib.HelperInstallCode = PrivilegedHelperTool.isHelperToolInstalled();

    self.state.lock();
    defer self.state.unlock();

    if (installCheckResult == freetracer_lib.HelperInstallCode.SUCCESS) {
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
        processResponseMessage(connection, message);
    }
}

fn processResponseMessage(connection: XPCConnection, data: XPCObject) void {
    const response: HelperResponseCode = XPCService.parseResponse(data);

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
        },
    }

    _ = connection;
}

fn shouldHelperUpdate(dict: XPCObject) bool {
    const version = XPCService.parseString(dict, "version");
    Debug.log(.INFO, "Helper reported version is: {s}", .{version});
    return !std.mem.eql(u8, version, AppConfig.PRIVILEGED_TOOL_LATEST_VERSION);
}

fn waitForHelperToolInstall() void {
    Debug.log(.INFO, "Waiting to allow Helper Tool be registered with system launch daemon", .{});
    std.time.sleep(1_000_000_000);
}

fn installHelperIfNotInstalled(self: *PrivilegedHelper) !void {
    if (!self.isHelperInstalled) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        waitForHelperToolInstall();

        if (installResult == freetracer_lib.HelperInstallCode.SUCCESS) {
            Debug.log(.INFO, "Fretracer Helper Tool is successfully installed!", .{});
            self.dispatchComponentAction();
        } else return error.FailedToInstallPrivilegedHelperTool;
    } else Debug.log(.INFO, "Determined that Freetracer Helper Tool is already installed.", .{});
}

fn requestUnmount(self: *PrivilegedHelper, targetDisk: [:0]const u8) void {
    // Install or update the Privileged Helper Tool before sending unmount request

    Debug.log(.DEBUG, "requestUnmount received targetDisk: {s}", .{targetDisk});

    if (targetDisk.len < 2) {
        Debug.log(.ERROR, "PrivilegedHelper.requestUnmount(): malformed targetDisk ('{any}') Aborting...", .{targetDisk});
        return;
    }

    const request = XPCService.createRequest(.WRITE_ISO_TO_DEVICE);
    defer XPCService.releaseObject(request);
    XPCService.createString(request, "disk", targetDisk);
    XPCService.connectionSendMessage(self.xpcClient.service, request);

    // for (0..AppConfig.MACH_PORT_REMOTE_MAX_TEST_ATTEMPTS) |i| {
    //     Debug.log(.DEBUG, "Attempting to test remote port to Helper Tool, attempt {d}...", .{i + 1});
    //     const testAttemptResult = self.machCommunicator.testRemotePort();
    //     if (testAttemptResult) break;
    //     waitForHelperToolInstall();
    // }
    //
    // const helperVersionBuffer = PrivilegedHelperTool.requestHelperVersion() catch |err| blk: {
    //     Debug.log(.WARNING, "Unable to retrieve Helper Tool's installed version. Error: {any}", .{err});
    //     break :blk std.mem.zeroes([MachPortPacketSize]u8);
    // };
    //
    // const helperVersion: [:0]const u8 = @ptrCast(std.mem.sliceTo(&helperVersionBuffer, 0x00));
    //
    // if (helperVersion.len < 1) {
    //     Debug.log(.ERROR, "Helper Tool responded with zero version length response despite just having been installed. Aborting...", .{});
    //     return freetracer_lib.HelperUnmountRequestCode.FAILURE;
    // }
    //
    // Debug.log(.INFO, "Freetracer received confirmation of Helper Tool version [{s}] installed.", .{helperVersion});
    //
    // if (!std.mem.eql(u8, AppConfig.PRIVILEGED_TOOL_LATEST_VERSION, helperVersion)) {
    //     const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
    //     waitForHelperToolInstall();
    //     if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) return freetracer_lib.HelperUnmountRequestCode.FAILURE;
    //     return freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN;
    // }
    //
    // const returnCode = PrivilegedHelperTool.requestPerformUnmount(targetDisk) catch |err| blk: {
    //     Debug.log(.ERROR, "PrivilegedHelper.requestUnmount() caught an error: {any}", .{err});
    //     break :blk freetracer_lib.HelperUnmountRequestCode.FAILURE;
    // };
    // return returnCode;

    // return freetracer_lib.HelperUnmountRequestCode.SUCCESS;
}

fn acquireStateDataOwnership(self: *PrivilegedHelper, isoPath: [:0]const u8, targetDisk: [:0]const u8) !void {
    self.cleanupComponentState();
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isoPath = try self.allocator.dupeZ(u8, isoPath);
    self.state.data.targetDisk = try self.allocator.dupeZ(u8, targetDisk);
    Debug.log(.INFO, "Set to state: \n\tISO Path: {s}\n\ttargetDisk: {s}", .{ self.state.data.isoPath.?, self.state.data.targetDisk.? });
}

fn cleanupComponentState(self: *PrivilegedHelper) void {
    self.state.lock();
    defer self.state.unlock();

    if (self.state.data.isoPath) |path| self.allocator.free(path);
    if (self.state.data.targetDisk) |disk| self.allocator.free(disk);
}

fn processMachMessage(msgId: i32, data: SerializedData) !SerializedData {
    Debug.log(.INFO, "Received message {any} and data {any}", .{ msgId, data });
    return SerializedData.serialize([:0]const u8, "Successful response from MAIN APP!");
}

pub fn requestWrite(data: [:0]const u8) freetracer_lib.HelperReturnCode {
    const returnCode = PrivilegedHelperTool.requestWriteISO(data) catch |err| blk: {
        Debug.log(.ERROR, "PrivilegedHelper.requestWrite() caught an error: {any}", .{err});
        break :blk freetracer_lib.HelperReturnCode.FAILED_TO_WRITE_ISO_TO_DEVICE;
    };

    return returnCode;
}

const ComponentImplementation = ComponentFramework.ImplementComponent(PrivilegedHelper);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
