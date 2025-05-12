const std = @import("std");

const GenericComponent = @import("./import/index.zig").GenericComponent;

pub const ComponentRegistry = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(GenericComponent),

    pub fn init(allocator: std.mem.Allocator) ComponentRegistry {
        return .{
            .allocator = allocator,
            .components = std.ArrayList(GenericComponent).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentRegistry) void {
        for (self.components.items) |component| {
            component.deinit();
        }
        self.components.deinit();
    }

    pub fn register(self: *ComponentRegistry, component: GenericComponent) !void {
        try self.components.append(component);
        try component.initComponent();
    }

    pub fn updateAll(self: *ComponentRegistry) !void {
        for (self.components.items) |component| {
            try component.update();
        }
    }

    pub fn drawAll(self: *ComponentRegistry) !void {
        for (self.components.items) |component| {
            try component.draw();
        }
    }
};
