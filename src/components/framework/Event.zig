const std = @import("std");
const Component = @import("./import/index.zig").Component;

pub const EventCreationParams = struct {
    name: []const u8,
    hash: EventHash,
    source: *Component,
    target: ?*Component = null,
    data: ?*const anyopaque = null,
};

pub const ComponentEvent = struct {
    name: []const u8,
    hash: EventHash,
    source: *Component,
    target: ?*Component = null,
    data: ?*const anyopaque = null,
    handled: bool = false,

    pub fn create(params: EventCreationParams) ComponentEvent {
        return ComponentEvent{
            .name = params.name,
            .hash = params.hash,
            .source = params.source,
            .target = params.target,
            .data = params.data,
        };
    }
};

pub const EventHash = u64;

pub fn hashEvent(comptime event_name: []const u8) EventHash {
    return comptime @as(EventHash, std.hash_map.hashString(event_name));
}

pub fn defineEvent(comptime name: []const u8, comptime DataType: type) type {
    return struct {
        pub const Hash = hashEvent(name);
        pub const Data = DataType;
        pub const Name = name;

        pub fn create(source: *Component, data: *const Data) ComponentEvent {
            return ComponentEvent.create(.{
                .name = Name,
                .hash = Hash,
                .source = source,
                .data = @ptrCast(@alignCast(data)),
            });
        }

        pub fn matches(event: *const ComponentEvent) bool {
            return event.hash == Hash;
        }

        pub fn getData(event: *const ComponentEvent) ?*const Data {
            if (event.hash == Hash and event.data != null) {
                return @ptrCast(@alignCast(event.data.?));
            }
            return null;
        }
    };
}
