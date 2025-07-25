const std = @import("std");
const Component = @import("./import/index.zig").Component;

pub const EventCreationParams = struct {
    name: []const u8,
    hash: EventHash,
    source: ?*Component,
    target: ?*Component = null,
    data: ?*const anyopaque = null,
};

pub const EventFlags = struct {
    overrideNotifySelfOnSelfOrigin: bool = false,
};

pub const ComponentEvent = struct {
    name: []const u8,
    hash: EventHash,
    source: ?*Component,
    target: ?*Component = null,
    data: ?*const anyopaque = null,
    handled: bool = false,
    flags: EventFlags = .{},

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

pub const EventResult = struct {
    success: bool = false,
    validation: EventValidation = .FAILURE,
    data: ?*anyopaque = null,

    pub const EventValidation = enum(u1) {
        FAILURE = 0,
        SUCCESS = 1,
    };

    pub fn init() EventResult {
        return EventResult{};
    }

    pub fn validate(self: *EventResult, validation: EventValidation) void {
        self.success = true;
        self.validation = validation;
    }
};

pub fn hashEvent(comptime event_name: []const u8) EventHash {
    return comptime @as(EventHash, std.hash_map.hashString(event_name));
}

pub fn defineEvent(comptime name: []const u8, comptime DataType: type, comptime ResponseType: type) type {
    return struct {
        pub const Hash = hashEvent(name);
        pub const Data = DataType;
        pub const Response = ResponseType;
        pub const Name = name;

        pub fn create(source: ?*Component, data: ?*const Data) ComponentEvent {
            return ComponentEvent.create(.{
                .name = Name,
                .hash = Hash,
                .source = source,
                .data = if (data != null) @ptrCast(@alignCast(data)) else null,
            });
        }

        pub fn matches(event: *const ComponentEvent) bool {
            return event.hash == Hash;
        }

        pub fn getData(event: ComponentEvent) ?*const Data {
            if (event.hash == Hash and event.data != null) {
                return @ptrCast(@alignCast(event.data.?));
            }
            return null;
        }
    };
}
