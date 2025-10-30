const std = @import("std");
const testing = std.testing;
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

pub const EventResultDetail = enum {
    None,
    IncorrectImagePath,
    IncorrectDeviceBSDName,
    FailedToTransitionState,
    FailedToInstallHelper,
    FailedWriteRequest,
};

pub const EventResult = struct {
    success: bool = false,
    validation: EventValidation = .FAILURE,
    data: ?*anyopaque = null,
    detail: EventResultDetail = .None,

    pub const EventValidation = enum(u1) {
        FAILURE = 0,
        SUCCESS = 1,
    };

    pub fn init() EventResult {
        return EventResult{};
    }

    pub fn succeed(self: *EventResult) EventResult {
        self.success = true;
        self.validation = .SUCCESS;
        return self.*;
    }

    pub fn fail(self: *EventResult) EventResult {
        self.success = false;
        self.validation = .FAILURE;
        return self.*;
    }

    pub fn failWithDetail(self: *EventResult, detail: EventResultDetail) EventResult {
        self.detail = detail;
        return self.fail();
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

// --- Tests ---

test "hashEvent computes correct hash" {
    const event_name = "TestEvent";
    const expected_hash = std.hash_map.hashString(event_name);
    const actual_hash = hashEvent(event_name);
    try testing.expectEqual(expected_hash, actual_hash);
}

test "defineEvent creates a valid event structure" {
    const MyEvent = defineEvent("MyEvent", struct { value: i32 }, struct { status: bool });

    // 1. Check compile-time constants
    try testing.expectEqualStrings("MyEvent", MyEvent.Name);
    try testing.expectEqual(hashEvent("MyEvent"), MyEvent.Hash);
    try testing.expect(@TypeOf(MyEvent.Data) == struct { value: i32 });
    try testing.expect(@TypeOf(MyEvent.Response) == struct { status: bool });

    // 2. Test event creation
    var source_component = Component{ .id = 123 };
    const event_data = MyEvent.Data{ .value = 42 };
    var event = MyEvent.create(&source_component, &event_data);

    try testing.expectEqualStrings(MyEvent.Name, event.name);
    try testing.expectEqual(MyEvent.Hash, event.hash);
    try testing.expect(event.source == &source_component);
    try testing.expect(event.target == null);
    try testing.expect(event.data != null);

    // 3. Test matches function
    try testing.expect(MyEvent.matches(&event));

    const AnotherEvent = defineEvent("AnotherEvent", u8, void);
    var another_event = AnotherEvent.create(null, null);
    try testing.expect(!MyEvent.matches(&another_event));

    // 4. Test getData function
    const retrieved_data = MyEvent.getData(event);
    try testing.expect(retrieved_data != null);
    try testing.expectEqual(@as(i32, 42), retrieved_data.?.value);

    // Test getData with a mismatched event
    const null_data = MyEvent.getData(another_event);
    try testing.expect(null_data == null);

    // Test getData with a matching event but no data
    const event_no_data = MyEvent.create(&source_component, null);
    const retrieved_no_data = MyEvent.getData(event_no_data);
    try testing.expect(retrieved_no_data == null);
}

test "ComponentEvent.create initializes correctly" {
    var source_comp = Component{ .id = 1 };
    var target_comp = Component{ .id = 2 };
    const data: u32 = 1337;

    const params = EventCreationParams{
        .name = "DirectCreate",
        .hash = hashEvent("DirectCreate"),
        .source = &source_comp,
        .target = &target_comp,
        .data = &data,
    };

    const event = ComponentEvent.create(params);

    try testing.expectEqualStrings("DirectCreate", event.name);
    try testing.expectEqual(hashEvent("DirectCreate"), event.hash);
    try testing.expect(event.source == &source_comp);
    try testing.expect(event.target == &target_comp);
    try testing.expect(event.data == &data);
    try testing.expectEqual(false, event.handled);
    try testing.expectEqual(false, event.flags.overrideNotifySelfOnSelfOrigin);
}

test "EventResult initialization and validation" {
    // 1. Test init
    var result = EventResult.init();
    try testing.expectEqual(false, result.success);
    try testing.expectEqual(EventResult.EventValidation.FAILURE, result.validation);
    try testing.expect(result.data == null);

    // 2. Test validate with SUCCESS
    result.validate(.SUCCESS);
    try testing.expectEqual(true, result.success);
    try testing.expectEqual(EventResult.EventValidation.SUCCESS, result.validation);

    // 3. Test validate with FAILURE
    result.validate(.FAILURE);
    try testing.expectEqual(true, result.success); // Success is true because validate was called
    try testing.expectEqual(EventResult.EventValidation.FAILURE, result.validation);
}
