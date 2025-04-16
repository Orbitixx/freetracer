const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const FilePicker = @import("FilePicker/Index.zig");
const USBDevicesList = @import("USBDevicesList/Index.zig");

const AppController = @import("../AppController.zig");

pub const Component = union(enum) {
    FilePicker: *FilePicker.Component,
    USBDevicesList: *USBDevicesList.Component,

    pub fn getSelf(self: Component) Component {
        switch (self) {
            inline else => |s| return s,
        }
    }

    pub fn draw(self: Component) void {
        switch (self) {
            inline else => |s| s.draw(),
        }
    }

    pub fn update(self: Component) void {
        switch (self) {
            inline else => |s| s.update(),
        }
    }

    pub fn deinit(self: Component) void {
        switch (self) {
            inline else => |s| s.deinit(),
        }
    }
};

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
