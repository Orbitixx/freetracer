const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const AppObserverEvent = @import("../observers/AppObserver.zig").Event;

const Component = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    // init: *const fn (*anyopaque, allocator: std.mem.Allocator) anyerror!Component,
    draw: *const fn (*anyopaque) void,
    update: *const fn (*anyopaque) void,
    deinit: *const fn (*anyopaque) void,
    notify: *const fn (*anyopaque, event: AppObserverEvent) void,
};

// pub fn init(allocator: std.mem.Allocator) Component {
//     return self.vtable.init(self.ptr, allocator);
// }

pub fn draw(self: Component) void {
    self.vtable.draw(self.ptr);
}

pub fn update(self: Component) void {
    self.vtable.update(self.ptr);
}

pub fn deinit(self: Component) void {
    self.vtable.deinit(self.ptr);
}

pub fn notify(self: Component, event: AppObserverEvent) void {
    self.vtable.notify(self.ptr, event);
}
