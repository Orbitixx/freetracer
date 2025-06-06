const std = @import("std");
const ComponentState = @import("./import/index.zig").ComponentState;

const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

const EventFramework = @import("Event.zig");
const ComponentEvent = EventFramework.ComponentEvent;
const EventResult = EventFramework.EventResult;

pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    parent: ?*Component = null,
    children: ?std.ArrayList(Component) = null,

    pub const VTable = struct {
        start_fn: *const fn (ptr: *anyopaque) anyerror!void,
        deinit_fn: *const fn (ptr: *anyopaque) void,
        update_fn: *const fn (ptr: *anyopaque) anyerror!void,
        draw_fn: *const fn (ptr: *anyopaque) anyerror!void,
        handle_event_fn: *const fn (ptr: *anyopaque, event: ComponentEvent) anyerror!EventResult,
        dispatch_action_fn: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(ptr: *anyopaque, vtable: *const VTable, parent: ?*Component) !Component {
        return Component{
            .ptr = ptr,
            .vtable = vtable,
            .parent = parent,
        };
    }

    pub fn start(self: Component) !void {
        return self.vtable.start_fn(self.ptr);
    }

    pub fn update(self: Component) !void {
        // std.debug.print("\nBase Component.update() called.", .{});

        if (self.children) |children| {
            // std.debug.print("\nBase Component.update(): found children, attempting to update children...", .{});
            if (children.items.len > 0) {
                for (children.items) |*child| {
                    // std.debug.print("\nBase Component.update(): updating a specific child...", .{});
                    try child.update();
                }
            }
        }

        return self.vtable.update_fn(self.ptr);
    }

    pub fn draw(self: Component) !void {
        // std.debug.print("\nBase Component.draw() called.", .{});

        if (self.children) |children| {
            // std.debug.print("\nBase Component.draw(): found children, attempting to draw children...", .{});
            if (children.items.len > 0) {
                for (children.items) |*child| {
                    // std.debug.print("\nBase Component.draw(): drawing a specific child...", .{});
                    try child.draw();
                }
            }
        }
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

    pub fn handleEvent(self: Component, event: ComponentEvent) !EventResult {
        return self.vtable.handle_event_fn(self.ptr, event);
    }

    pub fn dispatchComponentAction(self: Component) void {
        return self.vtable.dispatch_action_fn(self.ptr);
    }

    pub fn deinit(self: *Component) void {
        std.debug.print("\nGeneric Component deinit() called!", .{});

        if (self.children) |children| {
            std.debug.print("\nGeneric Component deinit(): component has children.", .{});

            for (children.items) |*child| {
                child.deinit();
            }
            children.deinit();

            std.debug.print("\nGeneric Component deinit(): children have been cleaned up.", .{});
        }

        self.children = null;
        self.parent = null;

        return self.vtable.deinit_fn(self.ptr);
    }
};

pub fn ImplementComponent(comptime T: type) type {
    return struct {
        //
        pub const vtable = Component.VTable{
            .start_fn = startWrapper,
            .update_fn = updateWrapper,
            .deinit_fn = deinitWrapper,
            .draw_fn = drawWrapper,
            .handle_event_fn = handleEventWrapper,
            .dispatch_action_fn = dispatchActionWrapper,
        };

        pub fn asComponent(self: *T) Component {
            return self.component.?;
        }

        pub fn asComponentPtr(self: *T) *Component {
            // TODO: contemplate the impact of null here.

            if (self.component == null) self.initComponent(null) catch |err| {
                std.debug.print("\nError initializing Base Component for Component type: {any}, error: {any}", .{ T, err });
            };

            return &self.component.?;
        }

        pub fn asInstance(ptr: *anyopaque) *T {
            return @ptrCast(@alignCast(ptr));
        }

        fn startWrapper(ptr: *anyopaque) anyerror!void {
            return asInstance(ptr).start();
        }

        fn updateWrapper(ptr: *anyopaque) anyerror!void {
            return asInstance(ptr).update();
        }

        fn deinitWrapper(ptr: *anyopaque) void {
            return asInstance(ptr).deinit();
        }

        fn drawWrapper(ptr: *anyopaque) anyerror!void {
            return asInstance(ptr).draw();
        }

        fn handleEventWrapper(ptr: *anyopaque, event: ComponentEvent) anyerror!EventResult {
            return asInstance(ptr).handleEvent(event);
        }

        fn dispatchActionWrapper(ptr: *anyopaque) void {
            return asInstance(ptr).dispatchComponentAction();
        }
    };
}
