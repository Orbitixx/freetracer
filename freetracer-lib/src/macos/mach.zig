const std = @import("std");
const k = @import("../constants.zig").k;
const Debug = @import("../util/debug.zig");

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
});

const NullTerminatedStringType: type = [:0]const u8;

pub const SerializedData = struct {
    data: [k.ResponseDataSize]u8,

    pub fn serializeString(str: [:0]const u8) SerializedData {
        std.debug.assert(str.len + 1 <= k.ResponseDataSize); // +1 for null terminator
        var data = std.mem.zeroes([k.ResponseDataSize]u8);

        // Copy the string content (without the null terminator from the slice)
        @memcpy(data[0..str.len], str);

        // Explicitly add null terminator
        data[str.len] = 0;

        return .{ .data = data };
    }

    pub fn deserializeString(sData: SerializedData) [:0]const u8 {
        // Find the null terminator to determine string length
        const len = std.mem.indexOfScalar(u8, &sData.data, 0) orelse {
            // If no null terminator found, assume the entire buffer is used
            // This is a fallback, but ideally strings should be null-terminated
            std.debug.panic("No null terminator found in serialized string data", .{});
        };

        // Return a null-terminated slice pointing to the data
        return sData.data[0..len :0];
    }

    pub fn serialize(comptime T: type, rdata: *T) SerializedData {
        std.debug.assert(@sizeOf(T) <= k.ResponseDataSize);

        var data = std.mem.zeroes([k.ResponseDataSize]u8);
        const bytes = std.mem.asBytes(rdata);

        @memcpy(data[0..bytes.len], bytes);

        return .{ .data = data };
    }

    pub fn deserialize(comptime T: type, sData: SerializedData) T {
        var sArray: [k.ResponseDataSize]u8 = sData.data;
        return std.mem.bytesAsValue(T, &sArray).*;
    }

    pub fn constructCFDataRef(self: SerializedData) c.CFDataRef {
        return c.CFDataCreate(c.kCFAllocatorDefault, @ptrCast(&self.data), @intCast(self.data.len));
    }

    pub fn destructCFDataRef(dataRef: c.CFDataRef) !SerializedData {
        if (dataRef == null) return error.CFDataRefIsNULL;

        const sourceData = @as([*]const u8, c.CFDataGetBytePtr(dataRef))[0..@intCast(c.CFDataGetLength(dataRef))];

        var finalByteArray: [k.ResponseDataSize]u8 = std.mem.zeroes([k.ResponseDataSize]u8);
        @memcpy(finalByteArray[0..sourceData.len], sourceData);

        return SerializedData{
            .data = finalByteArray,
        };
    }
};

pub const MachCommunicator = struct {
    pub const MachCommunicatorConfig = struct {
        bundleId: []const u8,
        ownerName: []const u8,
        processMessageFn: *const fn (msgId: i32, requestData: SerializedData) anyerror!SerializedData,
    };

    pub var AppName: []const u8 = "UNKNOWN";
    pub var processMessageFn: *const fn (msgId: i32, requestData: SerializedData) anyerror!SerializedData = MachCommunicator.defaultProcessMessageFn;

    config: MachCommunicatorConfig,
    allocator: std.mem.Allocator,
    localMessagePortNameRef: c.CFStringRef = null,
    localMessagePortContext: c.CFMessagePortContext = .{},
    shouldFreeMessagePortInfo: c.Boolean = c.FALSE,
    localMessagePortRef: c.CFMessagePortRef = null,
    runLoopSourceRef: c.CFRunLoopSourceRef = null,

    pub fn init(allocator: std.mem.Allocator, config: MachCommunicatorConfig) MachCommunicator {
        AppName = config.ownerName;
        processMessageFn = config.processMessageFn;

        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn start(self: *MachCommunicator) !void {
        self.localMessagePortNameRef = c.CFStringCreateWithCStringNoCopy(
            c.kCFAllocatorDefault,
            @ptrCast(self.config.bundleId),
            c.kCFStringEncodingUTF8,
            c.kCFAllocatorNull,
        );

        self.localMessagePortContext = c.CFMessagePortContext{
            .version = 0,
            .copyDescription = null,
            .info = null,
            .release = null,
            .retain = null,
        };

        self.localMessagePortRef = c.CFMessagePortCreateLocal(
            c.kCFAllocatorDefault,
            self.localMessagePortNameRef,
            MachCommunicator.onMessageReceived,
            &self.localMessagePortContext,
            &self.shouldFreeMessagePortInfo,
        );

        if (self.localMessagePortRef == null) {
            Debug.log(.ERROR, "{s}: unable to create a local message port.", .{AppName});
            return;
        }

        const kRunLoopOrder: c.CFIndex = 0;

        const runLoopSource: c.CFRunLoopSourceRef = c.CFMessagePortCreateRunLoopSource(c.kCFAllocatorDefault, self.localMessagePortRef, kRunLoopOrder);
        c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), runLoopSource, c.kCFRunLoopDefaultMode);

        Debug.log(.INFO, "{s}: MachCommunicator started. Awaiting requests...", .{AppName});

        c.CFRunLoopRun();
    }

    // NOTE: Static function/callback. Arguments are frozen and dictacted by c.CFMessagePortCreateLocal signature.
    pub fn onMessageReceived(port: c.CFMessagePortRef, msgId: c.SInt32, data: c.CFDataRef, info: ?*anyopaque) callconv(.C) c.CFDataRef {
        var returnData: c.CFDataRef = null;

        _ = port;
        _ = info;

        Debug.log(.INFO, "{s}: onMessageReceived callback executing...", .{AppName});

        const requestData = SerializedData.destructCFDataRef(@ptrCast(data)) catch |err| {
            Debug.log(.WARNING, "{s}: onMessageReceived(): received NULL data as parameter. Error: {any}. Ignoring request...", .{ AppName, err });
            return returnData;
        };

        if (requestData.data.len < 1) {
            Debug.log(.WARNING, "{s}: The received length of the request data is 0.", .{AppName});
            return returnData;
        }

        Debug.log(.INFO, "{s}: Request data received: {any}\n", .{ AppName, requestData.data });

        // var responseData: SerializedData = SerializedData{ .data = "CRITICAL_ERROR" };

        var responseData = processMessageFn(msgId, requestData) catch |err| blk: {
            Debug.log(.ERROR, "{s}: onMessageReceived.processRequestMessage(msgId = {d}) returned an error: {any}", .{ AppName, msgId, err });
            break :blk SerializedData{ .data = std.mem.zeroes([k.ResponseDataSize]u8) };
        };

        Debug.log(.INFO, "responseData is: {any}", .{responseData.data});

        returnData = @ptrCast(responseData.constructCFDataRef());

        Debug.log(.INFO, "{s}: Successfully packaged response: {any}.", .{ AppName, responseData.data });

        return returnData;
    }

    pub fn deinit(self: MachCommunicator) void {
        // defer is used to preserve execution order to follow the order
        // in which these were initialized/allocated.
        defer _ = c.CFRelease(self.localMessagePortNameRef);
        defer _ = c.CFRelease(self.localMessagePortRef);
        defer _ = c.CFRelease(self.runLoopSourceRef);
        defer c.CFRunLoopSourceInvalidate(self.runLoopSourceRef);
    }

    pub fn defaultProcessMessageFn(msgId: i32, requestData: SerializedData) !SerializedData {
        _ = msgId;
        _ = requestData;

        return error.MachCommunicatorProcessMessageFunctionNotInitialized;
    }
};
