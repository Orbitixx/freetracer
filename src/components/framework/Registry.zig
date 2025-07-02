const std = @import("std");

const Component = @import("./import/index.zig").Component;

pub const ComponentID = enum(u8) {
    ISOFilePicker = 0,
    DeviceList = 1,
    DataFlasher = 2,
    TestBtn = 99,
};

pub const ComponentRegistry = struct {
    allocator: std.mem.Allocator,
    components: std.AutoHashMap(ComponentID, *Component),

    pub fn init(allocator: std.mem.Allocator) ComponentRegistry {
        return .{
            .allocator = allocator,
            .components = std.AutoHashMap(ComponentID, *Component).init(allocator),
        };
    }

    pub fn register(self: *ComponentRegistry, componentId: ComponentID, component: *Component) !void {
        try self.components.put(componentId, component);
    }

    pub fn startAll(self: *ComponentRegistry) !void {
        _ = self;
        // var iter = self.components.iterator();
        //
        // while (iter.next()) |component| {
        //     try component.value_ptr.*.start();
        // }
    }

    pub fn updateAll(self: *ComponentRegistry) !void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            try component.value_ptr.*.update();
        }
    }

    pub fn drawAll(self: *ComponentRegistry) !void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            try component.value_ptr.*.draw();
        }
    }

    pub fn deinit(self: *ComponentRegistry) void {
        var iter = self.components.iterator();

        while (iter.next()) |component| {
            component.value_ptr.*.deinit();
        }

        self.components.deinit();
    }
};
