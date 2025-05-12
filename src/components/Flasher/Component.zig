// const std = @import("std");
//
// const debug = @import("../../lib/util/debug.zig");
// const String = @import("../../lib/util/strings.zig");
// const UI = @import("../../lib/ui/ui.zig");
//
// const MacOS = @import("../../modules/macos/MacOSTypes.zig");
// const IOKit = @import("../../modules/macos/IOKit.zig");
//
// const Thread = std.Thread;
//
// const AppObserverF = @import("../../observers/AppObserver.zig");
// const AppObserver = AppObserverF.AppObserver;
// const Event = AppObserverF.Event;
// const EventPayload = AppObserverF.Payload;
//
// const Component = @import("../Component.zig");
//
// const FlasherComponent = @This();
// const FlasherState = @import("State.zig");
// const FlasherWorker = @import("Worker.zig");
//
// const ComponentUI = @import("UI.zig");
//
// allocator: std.mem.Allocator,
// state: *FlasherState,
// appObserver: *const AppObserver,
// worker: ?std.Thread = null,
// componentActive: bool = false,
// device: ?MacOS.USBStorageDevice = null,
// ui: ComponentUI,
//
// pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) FlasherComponent {
//     const state = allocator.create(FlasherState) catch |err| {
//         debug.printf("\nERROR: Unable to allocate memory for FlasherState. {any}", .{err});
//         std.debug.panic("\n{any}", .{err});
//     };
//
//     state.* = .{
//         .allocator = allocator,
//         // .device = MacOS.USBStorageDevice{ },
//     };
//
//     var component: FlasherComponent = .{
//         .allocator = allocator,
//         .appObserver = appObserver,
//         .state = state,
//         .ui = .{
//             .allocator = allocator,
//             .appObserver = appObserver,
//         },
//     };
//
//     component.ui.init();
//
//     return component;
// }
//
// pub fn enable(self: *FlasherComponent) void {
//     self.componentActive = true;
//     self.ui.active = true;
//     self.ui.recalculateUi();
// }
//
// pub fn update(self: *FlasherComponent) void {
//     // if (self.componentActive) {
//     //     if (!self.devicesFound) {
//     //         debug.print("\nFlasherComponent: Dispatching component action...");
//     //         dispatchComponentAction(self);
//     //     }
//     //     self.componentActive = false;
//     // }
//
//     self.ui.update();
//
//     var workerFinished = false;
//
//     self.state.mutex.lock();
//
//     if (self.state.taskDone) {
//         debug.print("\nFlasherComponent: task done signal receieved.");
//         workerFinished = true;
//
//         if (self.state.devices.items.len > 0) {
//             self.devicesFound = true;
//
//             self.ui.setDevices(self, self.state.devices.items);
//         }
//
//         self.notify(.USB_DEVICES_DISCOVERED, .{});
//
//         self.componentActive = false;
//     }
//
//     self.state.mutex.unlock();
//
//     if (workerFinished) {
//         if (self.worker) |thread| {
//             debug.print("\nFlasherComponent: joining worker thread...");
//             thread.join();
//             self.worker = null;
//             debug.print("\nFlasherComponent: worker joined.");
//         }
//
//         self.state.mutex.lock();
//
//         self.state.taskDone = false;
//         self.state.taskRunning = false;
//
//         self.state.mutex.unlock();
//
//         debug.print("\nFlasherComponent: Finished finding USB devices.");
//     }
// }
//
// pub fn draw(self: *FlasherComponent) void {
//     self.ui.draw();
//     // if (!self.devicesFound) return;
// }
//
// pub fn deinit(self: *FlasherComponent) void {
//     if (self.worker) |thread| {
//         debug.print("FlasherComponent.deinit(): Joining worker thread...\n");
//         thread.join();
//         self.worker = null;
//     }
//
//     self.ui.deinit();
//     self.state.deinit();
//     self.allocator.destroy(self.state);
// }
//
// pub fn notify(self: *FlasherComponent, event: Event, payload: EventPayload) void {
//     self.appObserver.*.onNotify(event, payload);
// }
//
// pub fn notifyCallback(ctx: *anyopaque, event: Event, payload: EventPayload) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(ctx));
//     self.notify(event, payload);
// }
//
// pub fn asComponent(self: *const FlasherComponent) Component {
//     return Component{
//         .ptr = @constCast(self),
//         .vtable = &VTable,
//     };
// }
//
// pub fn macos_getDevice(self: *const FlasherComponent, bsdName: []u8) ?MacOS.USBStorageDevice {
//     self.state.mutex.lock();
//     defer self.state.mutex.unlock();
//
//     if (self.state.devices.items.len < 1) return null;
//
//     for (self.state.devices.items) |device| {
//         debug.printf("\nmacos_getDevice(): comparing {s} and {s}, byte representation: \nstr1: {any}\nstr2: {any}", .{ device.bsdName, bsdName, String.truncToNull(device.bsdName), String.truncToNull(bsdName) });
//         if (String.eql(String.truncToNull(device.bsdName), String.truncToNull(bsdName))) return device;
//     }
//
//     std.debug.panic("\nWARNING: FlasherComponent() -> macos_getDevice() returned NULL for device '{s}'", .{bsdName});
//
//     return null;
// }
//
// pub fn dispatchComponentAction(self: *FlasherComponent) void {
//     self.state.mutex.lock();
//
//     if (self.state.taskRunning) {
//         debug.print("\nWARNING! FlasherComponent: worker task already running!");
//         self.state.mutex.unlock();
//         return;
//     }
//
//     debug.print("\nFlasherComponent: Starting worker...");
//
//     self.state.taskRunning = true;
//     self.state.taskDone = false;
//     self.state.taskError = null;
//
//     // Clear out old devices
//     if (self.state.devices.items.len > 0) {
//         for (self.state.devices.items) |device| {
//             device.deinit();
//         }
//         self.state.devices.clearAndFree();
//     }
//
//     self.state.mutex.unlock();
//
//     self.worker = Thread.spawn(.{}, FlasherWorker.run, .{ self.allocator, self.state }) catch blk: {
//         debug.print("\nERROR! FlasherComponent: Failed to spawn worker.\n");
//
//         self.state.mutex.lock();
//         // Reset state
//         self.state.taskDone = false;
//         self.state.taskRunning = false;
//         self.state.taskError = error.FailedToSpawnFlasherWorker;
//
//         self.state.mutex.unlock();
//         break :blk null;
//     };
//
//     debug.print("\nFlasherComponent: Finished worker dispatch.");
// }
//
// // --- Component Interface Implementation -------------------------//
// // Below methods are intended to be called internally within the struct only.
// // Use public implementations above: enable, update, draw, notify, deinit...
//
// const VTable = Component.VTable{
//     .enable = rawEnable,
//     .update = rawUpdate,
//     .draw = rawDraw,
//     .notify = rawNotify,
//     .deinit = rawDeinit,
// };
//
// fn rawEnable(selfOpaque: *anyopaque) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(selfOpaque));
//     return FlasherComponent.enable(self);
// }
//
// fn rawUpdate(selfOpaque: *anyopaque) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(selfOpaque));
//     return FlasherComponent.update(self);
// }
//
// fn rawDraw(selfOpaque: *anyopaque) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(selfOpaque));
//     return FlasherComponent.draw(self);
// }
//
// fn rawNotify(selfOpaque: *anyopaque, event: Event, payload: EventPayload) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(selfOpaque));
//     return FlasherComponent.notify(self, event, payload);
// }
//
// fn rawDeinit(selfOpaque: *anyopaque) void {
//     const self: *FlasherComponent = @ptrCast(@alignCast(selfOpaque));
//     return FlasherComponent.deinit(self);
// }
