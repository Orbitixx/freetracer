const std = @import("std");
const ComponentState = @import("./import/index.zig").ComponentState;

const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

const EventFramework = @import("Event.zig");
const ComponentEvent = EventFramework.ComponentEvent;

pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    parent: ?*Component = null,
    children: ?std.ArrayList(*Component) = null,

    pub const VTable = struct {
        start_fn: *const fn (ptr: *anyopaque) anyerror!void,
        deinit_fn: *const fn (ptr: *anyopaque) void,
        update_fn: *const fn (ptr: *anyopaque) anyerror!void,
        draw_fn: *const fn (ptr: *anyopaque) anyerror!void,
        handle_event_fn: *const fn (ptr: *anyopaque, event: ComponentEvent) anyerror!void,
        // notify_fn: *const fn (ptr: *anyopaque, event: ObserverEvent, payload: ObserverPayload) void,
    };

    pub fn init(ptr: *anyopaque, vtable: *const VTable) Component {
        return .{
            .ptr = ptr,
            .vtable = vtable,
        };
    }

    pub fn start(self: Component) !void {
        return self.vtable.start_fn(self.ptr);
    }

    pub fn update(self: Component) !void {
        return self.vtable.update_fn(self.ptr);
    }

    pub fn draw(self: Component) !void {
        return self.vtable.draw_fn(self.ptr);
    }

    pub fn notifyParent(self: Component, event: ComponentEvent) !void {
        if (self.parent == null) return error.ComponentFailedToNotifyNullParent;

        if (self.parent) |parent| {
            return parent.handleEvent(event);
        }
    }

    pub fn notifyChildren(self: Component, event: ComponentEvent) !void {
        if (self.children == null) return error.ComponentFailedToNotifyNullChildren;

        if (self.children) |children| {
            for (children.items) |child| {
                try child.handleEvent(event);
            }
        }
    }

    pub fn handleEvent(self: Component, event: ComponentEvent) !void {
        return self.vtable.handle_event_fn(self.ptr, event);
    }

    pub fn deinit(self: *Component) void {
        self.parent = null;

        if (self.children) |children| {
            if (children.items.len > 0) {
                for (children.items) |child| {
                    child.deinit();
                }
            }

            children.deinit();
        }

        self.children = null;

        return self.vtable.deinit_fn(self.ptr);
    }

    // pub fn notify(self: Component, event: ObserverEvent, payload: ObserverPayload) void {
    //     return self.vtable.notify_fn(self.ptr, event, payload);
    // }
};
