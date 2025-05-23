const Component = @import("./import/index.zig").Component;

pub const EventType = enum(u8) {
    UIWidthChanged,
};

pub const ComponentEvent = struct {
    eventType: EventType,
    data: ?*anyopaque = null,
    source: *Component,
    target: ?*Component = null,
    handled: bool = false,
};
