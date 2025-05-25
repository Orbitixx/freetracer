const Component = @import("./import/index.zig").Component;

pub const EventType = enum(u8) {
    UIWidthChanged,
};

pub const ComponentEvent = struct {
    title: []const u8,
    source: *Component,
    target: ?*Component = null,
    data: ?*const anyopaque = null,
    handled: bool = false,

    pub fn create(title: []const u8, source: *Component) ComponentEvent {
        return ComponentEvent{
            .title = title,
            .source = source,
        };
    }

    pub fn createWithData(title: []const u8, source: *Component, comptime T: type, data: *const T) ComponentEvent {
        return ComponentEvent{
            .title = title,
            .source = source,
            .data = @ptrCast(@alignCast(data)),
        };
    }
};
