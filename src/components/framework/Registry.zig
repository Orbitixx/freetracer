const std = @import("std");

const GenericComponent = @import("./import/index.zig").GenericComponent;

pub const ComponentID = enum(usize) {
    ISOFilePicker = 0,
};

pub const ComponentRegistry = struct {
    allocator: std.mem.Allocator,
    components: std.AutoHashMap(ComponentID, GenericComponent),

    pub fn init(allocator: std.mem.Allocator) ComponentRegistry {
        return .{
            .allocator = allocator,
            .components = std.AutoHashMap(ComponentID, GenericComponent).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentRegistry) void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            component.value_ptr.deinit();
        }

        self.components.deinit();
    }

    pub fn register(self: *ComponentRegistry, componentId: ComponentID, component: GenericComponent) !void {
        try self.components.put(componentId, component);
    }

    pub fn initAll(self: *ComponentRegistry) !void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            try component.value_ptr.initComponent();
        }
    }

    pub fn updateAll(self: *ComponentRegistry) !void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            try component.value_ptr.update();
        }
    }

    pub fn drawAll(self: *ComponentRegistry) !void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            try component.value_ptr.draw();
        }
    }
};
