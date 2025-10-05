const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const ComponentState = @import("./import/index.zig").ComponentState;

const EventFramework = @import("Event.zig");
const ComponentEvent = EventFramework.ComponentEvent;
const EventResult = EventFramework.EventResult;

pub const Component = struct {
    /// Represents the unique concrete instance implementing this
    /// interface as an opaque pointer. Must be @ptrCast and @alignCast
    /// to the concrete pointer of the implementing component. E.g.: *DataFlasher.
    ptr: *anyopaque,

    /// Pointer to the virtual table of the concrete component implementing this interface.
    vtable: *const VTable,

    /// Allocator used to manage the children ArrayList.
    allocator: std.mem.Allocator,

    /// Pointer to the Component property, which is an effective parent of some other
    /// concrete component implementing this interface.
    /// E.g.: DataFlasher.component: Component -> (parent of) DataFlasherUI.component: Component
    parent: ?*Component = null,

    /// List of Component objects which are canonical children of the component implementing this inferface.
    /// E.g.: DataFlasherUI.component: Component -> (child of) DataFlasher.component: Component
    children: ?std.ArrayList(Component) = null,

    /// Component interface virtual table, representing the required
    /// methods to be implemented by a specific/concrete component.
    pub const VTable = struct {
        start_fn: *const fn (ptr: *anyopaque) anyerror!void,
        deinit_fn: *const fn (ptr: *anyopaque) void,
        update_fn: *const fn (ptr: *anyopaque) anyerror!void,
        draw_fn: *const fn (ptr: *anyopaque) anyerror!void,
        handle_event_fn: *const fn (ptr: *anyopaque, event: ComponentEvent) anyerror!EventResult,
        dispatch_action_fn: *const fn (ptr: *anyopaque) void,
    };

    /// Instantiates an instance of the Component interface as a Component object.
    /// @Returns anyerror!Component.
    pub fn init(ptr: *anyopaque, vtable: *const VTable, parent: ?*Component, allocator: std.mem.Allocator) !Component {
        return Component{
            .ptr = ptr,
            .vtable = vtable,
            .parent = parent,
            .allocator = allocator,
        };
    }

    /// Called once upon component's instantiation. The start() Component interface method
    /// calls the component's implementation of start() for the purpose of initializing internal properties
    /// and performing respective startup routine.
    /// @Returns anyerror!void.
    pub fn start(self: Component) !void {
        return self.vtable.start_fn(self.ptr);
    }

    /// Called once per frame, the Component interface update() manages calling children's update()
    /// method first before calling the current component's implementation of update().
    /// @Returns anyerror!void.
    pub fn update(self: Component) !void {
        if (self.children) |children| {
            if (children.items.len > 0) {
                for (children.items) |*child| {
                    try child.update();
                }
            }
        }

        return self.vtable.update_fn(self.ptr);
    }

    /// Called once per frame, the Component interface draw() manages
    /// calling children's draw() method first before calling the current
    /// component's implementation of draw().
    /// @Returns anyerror!void.
    pub fn draw(self: Component) !void {
        if (self.children) |children| {
            if (children.items.len > 0) {
                for (children.items) |*child| {
                    try child.draw();
                }
            }
        }
        return self.vtable.draw_fn(self.ptr);
    }

    /// Contains the primary "event loop" of the concrete component and handles
    /// events defined within the pub const Events struct of the concrete component.
    /// @Returns anyerror!EventResult.
    pub fn handleEvent(self: Component, event: ComponentEvent) !EventResult {
        return self.vtable.handle_event_fn(self.ptr, event);
    }

    /// Contains the "primary action" of the concrete component implementing this interface.
    /// As a design choice, primary responsibiltiy of each component is defined within
    /// this method such that the primary action can be dispatched via a ComponentRegistry
    /// or another mechanism.
    /// @Returns void.
    pub fn dispatchComponentAction(self: Component) void {
        return self.vtable.dispatch_action_fn(self.ptr);
    }

    /// Cleanup function that is called upon the end of the component's lifecycle.
    /// @Returns void.
    pub fn deinit(self: *Component) void {
        if (self.children) |*children| {
            for (children.items) |*child| {
                child.deinit();
            }
            children.deinit(self.allocator);
        }

        self.children = null;
        self.parent = null;

        return self.vtable.deinit_fn(self.ptr);
    }
};

/// Helper function which allows to easily implement the Component interface within
/// each concrete component's body, reducing the code boilerplate required to be
/// re-implemented the same way within each such component. Provides helper methods
/// like asInstance() and asComponentPtr().
/// @Returns ConcreteComponentType, e.g.: DataFlasher.
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
                Debug.log(.ERROR, "Error initializing Base Component for Component type: {any}, error: {any}", .{ T, err });
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
