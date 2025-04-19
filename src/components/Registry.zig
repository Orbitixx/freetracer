const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const Component = @import("Component.zig");

pub const ComponentID = enum {
    ISOFilePicker,
    USBDevicesList,
};

pub const ComponentRegistry = struct {
    components: std.AutoHashMap(ComponentID, Component),

    pub fn registerComponent(self: *ComponentRegistry, componentId: ComponentID, component: Component) void {
        self.components.put(componentId, component) catch |err| {
            debug.printf("\nError: Unable to register component in the Component Registry via PUT. {any}", .{err});
            std.debug.panic("\n{any}", .{err});
        };
    }

    pub fn getComponent(self: ComponentRegistry, componentId: ComponentID) ?Component {
        return self.components.get(componentId);
    }

    pub fn processUpdates(self: ComponentRegistry) void {
        var iter = self.components.iterator();

        while (iter.next()) |pComponent| {
            pComponent.value_ptr.update();
        }
    }

    pub fn processRendering(self: ComponentRegistry) void {
        var iter = self.components.iterator();

        while (iter.next()) |pComponent| {
            pComponent.value_ptr.draw();
        }
    }

    pub fn deinit(self: *ComponentRegistry) void {
        var iter = self.components.iterator();
        while (iter.next()) |component| {
            component.value_ptr.deinit();
        }

        self.components.deinit();
    }
};

