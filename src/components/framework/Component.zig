const ComponentState = @import("./import/index.zig").ComponentState;

const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init_fn: *const fn (ptr: *anyopaque) anyerror!void,
        deinit_fn: *const fn (ptr: *anyopaque) void,
        update_fn: *const fn (ptr: *anyopaque) anyerror!void,
        draw_fn: *const fn (ptr: *anyopaque) anyerror!void,
        notify_fn: *const fn (ptr: *anyopaque, event: ObserverEvent, payload: ObserverPayload) void,
    };

    pub fn init(ptr: *anyopaque, vtable: *const VTable) Component {
        return .{ .ptr = ptr, .vtable = vtable };
    }

    pub fn initComponent(self: Component) !void {
        return self.vtable.init_fn(self.ptr);
    }

    pub fn deinit(self: Component) void {
        self.vtable.deinit_fn(self.ptr);
    }

    pub fn update(self: Component) !void {
        return self.vtable.update_fn(self.ptr);
    }

    pub fn draw(self: Component) !void {
        return self.vtable.draw_fn(self.ptr);
    }

    pub fn notify(self: Component, event: ObserverEvent, payload: ObserverPayload) void {
        return self.vtable.notify_fn(self.ptr, event, payload);
    }
};
