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

const PrivilegedHelperTool = @import("../../modules/macos/PrivilegedHelperTool.zig");

const PrivilegedHelperState = struct {
    isActive: bool = false,
    isHelperInstalled: bool = false,
    installedVersion: [:0]const u8 = "-1",
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
const EventResult = ComponentFramework.EventResult;

const PrivilegedHelper = @This();

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
machCommunicator: MachCommunicator,
isHelperInstalled: bool = false,

pub const Events = struct {
    //
    pub const onWriteISOToDeviceRequest = ComponentFramework.defineEvent(
        "privileged_helper.on_write_iso_to_device",
        struct {
            isoPath: [:0]const u8,
            targetDisk: [:0]const u8,
        },
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
        .machCommunicator = MachCommunicator.init(allocator, .{
            .localBundleId = @ptrCast(env.BUNDLE_ID),
            .remoteBundleId = @ptrCast(env.HELPER_BUNDLE_ID),
            .ownerName = "Freetracer Main Process",
            .processMessageFn = PrivilegedHelper.processMachMessage,
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

        if (!EventManager.subscribe("privileged_helper", component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "PrivilegedHelper: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        Debug.log(.DEBUG, "PrivilegedHelper: finished initializing children.", .{});
    }
}

pub fn update(self: *PrivilegedHelper) !void {
    if (System.isLinux) return;

    _ = self;
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
        Events.onWriteISOToDeviceRequest.Hash => {
            const data = Events.onWriteISOToDeviceRequest.getData(event) orelse break :eventLoop;

            var unmountResponse: freetracer_lib.HelperUnmountRequestCode = self.requestUnmount(data.targetDisk);

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
    _ = self;
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
    const installCheckResult: freetracer_lib.HelperInstallCode = PrivilegedHelperTool.isHelperToolInstalled();

    self.state.lock();
    defer self.state.unlock();

    if (installCheckResult == freetracer_lib.HelperInstallCode.SUCCESS) {
        self.isHelperInstalled = true;
    } else self.isHelperInstalled = false;
}

fn waitForHelperToolInstall() void {
    Debug.log(.INFO, "Waiting to allow Helper Tool be registered with system launch daemon", .{});

    std.time.sleep(3_000_000_000);
}

fn processMachMessage(msgId: i32, data: SerializedData) !SerializedData {
    Debug.log(.INFO, "Received message {any} and data {any}", .{ msgId, data });
    return SerializedData.serialize([:0]const u8, "Successful response from MAIN APP!");
}

fn requestUnmount(self: *PrivilegedHelper, targetDisk: [:0]const u8) freetracer_lib.HelperUnmountRequestCode {
    // Install or update the Privileged Helper Tool before sending unmount request

    if (!self.isHelperInstalled) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        waitForHelperToolInstall();
        if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) return freetracer_lib.HelperUnmountRequestCode.FAILURE else self.dispatchComponentAction();
        return freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN;
    }

    const helperPortNameRef: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(
        c.kCFAllocatorDefault,
        env.HELPER_BUNDLE_ID,
        c.kCFStringEncodingUTF8,
        c.kCFAllocatorNull,
    );

    const testRemotePort: c.CFMessagePortRef = c.CFMessagePortCreateRemote(c.kCFAllocatorDefault, helperPortNameRef);

    if (testRemotePort == null) {
        Debug.log(.WARNING, "Failed to establish a test remote port to the Helper Tool.", .{});
        waitForHelperToolInstall();
    } else Debug.log(.INFO, "Successfully established a test remote port to the helper tool.", .{});

    _ = c.CFRelease(testRemotePort);
    _ = c.CFRelease(helperPortNameRef);

    const helperVersionBuffer = PrivilegedHelperTool.requestHelperVersion() catch |err| blk: {
        Debug.log(.WARNING, "Unable to retrieve Helper Tool's installed version. Error: {any}", .{err});
        break :blk std.mem.zeroes([MachPortPacketSize]u8);
    };

    const helperVersion: [:0]const u8 = @ptrCast(std.mem.sliceTo(&helperVersionBuffer, 0x00));

    if (helperVersion.len < 1) {
        Debug.log(.ERROR, "Helper Tool responded with zero version length response despite just having been installed. Aborting...", .{});
        return freetracer_lib.HelperUnmountRequestCode.FAILURE;
    }

    Debug.log(.INFO, "Freetracer received confirmation of Helper Tool version [{s}] installed.", .{helperVersion});

    if (!std.mem.eql(u8, AppConfig.PRIVILEGED_TOOL_LATEST_VERSION, helperVersion)) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        waitForHelperToolInstall();
        if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) return freetracer_lib.HelperUnmountRequestCode.FAILURE;
        return freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN;
    }

    const returnCode = PrivilegedHelperTool.requestPerformUnmount(targetDisk) catch |err| blk: {
        Debug.log(.ERROR, "PrivilegedHelper.requestUnmount() caught an error: {any}", .{err});
        break :blk freetracer_lib.HelperUnmountRequestCode.FAILURE;
    };

    return returnCode;
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
