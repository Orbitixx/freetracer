const std = @import("std");
const rl = @import("raylib");
const AppConfig = @import("../../config.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const MachPortPacketSize = freetracer_lib.k.MachPortPacketSize;

const PrivilegedHelperTool = @import("../../modules/macos/PrivilegedHelperTool.zig");

const PrivilegedHelperState = struct {
    isActive: bool = false,
    isInstalled: bool = false,
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
isInstalled: bool = false,

pub const Events = struct {
    //
    pub const onUnmountDiskRequest = ComponentFramework.defineEvent(
        "privileged_helper.on_unmount_disk_request",
        struct {
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
            .isInstalled = System.isLinux,
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

    // Verify if the Helper Tool is installed and set self.isInstalled flag accordingly
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
    const isHelperToolInstalled = if (System.isMac) self.isInstalled else if (System.isLinux) true else unreachable;

    rl.drawCircleV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, if (isHelperToolInstalled) .green else .red);
    rl.drawCircleLinesV(.{ .x = winRelX(0.9), .y = winRelY(0.065) }, 4.5, .white);
}

pub fn handleEvent(self: *PrivilegedHelper, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    if (System.isLinux) return eventResult;

    eventLoop: switch (event.hash) {
        //
        Events.onUnmountDiskRequest.Hash => {
            const data = Events.onUnmountDiskRequest.getData(event) orelse break :eventLoop;

            var response: freetracer_lib.HelperUnmountRequestCode = self.requestUnmount(data.targetDisk);

            if (response == freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN) response = self.requestUnmount(data.targetDisk);

            Debug.log(.INFO, "PrivilegedHelper Component received response from Privileged Tool: {any}", .{response});

            if (response == freetracer_lib.HelperUnmountRequestCode.SUCCESS) eventResult.validate(1);
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
        self.isInstalled = true;
    } else self.isInstalled = false;
}

fn requestUnmount(self: *PrivilegedHelper, targetDisk: [:0]const u8) freetracer_lib.HelperUnmountRequestCode {
    // Install or update the Privileged Helper Tool before sending unmount request

    if (!self.isInstalled) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) return freetracer_lib.HelperUnmountRequestCode.FAILURE;
        return freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN;
    }

    const helperVersionBuffer = PrivilegedHelperTool.requestHelperVersion() catch |err| blk: {
        Debug.log(.WARNING, "Unable to retrieve Helper Tool's installed version, re-installing the Helper Tool. Error: {any}", .{err});
        break :blk std.mem.zeroes([MachPortPacketSize]u8);
    };

    const helperVersion: [:0]const u8 = @ptrCast(std.mem.sliceTo(&helperVersionBuffer, 0x00));

    Debug.log(.INFO, "Freetracer received confirmation of Helper Tool version [{s}] installed.", .{helperVersion});

    if (!std.mem.eql(u8, AppConfig.PRIVILEGED_TOOL_LATEST_VERSION, helperVersion)) {
        const installResult = PrivilegedHelperTool.installPrivilegedHelperTool();
        if (installResult != freetracer_lib.HelperInstallCode.SUCCESS) return freetracer_lib.HelperUnmountRequestCode.FAILURE;
        return freetracer_lib.HelperUnmountRequestCode.TRY_AGAIN;
    }

    return PrivilegedHelperTool.requestPerformUnmount(targetDisk);
}

const ComponentImplementation = ComponentFramework.ImplementComponent(PrivilegedHelper);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
