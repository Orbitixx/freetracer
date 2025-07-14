const std = @import("std");

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
});

pub const SerializedData = struct {
    data: []const u8,

    pub fn serialize(comptime T: type, dataPtr: *T) SerializedData {
        return .{ .data = std.mem.asBytes(dataPtr) };
    }

    pub fn deserialize(comptime T: type, data: SerializedData) T {
        return std.mem.bytesAsValue(T, data.data[0..]).*;
    }

    pub fn constructCFDataRef(self: SerializedData) c.CFDataRef {
        return c.CFDataCreate(c.kCFAllocatorDefault, self.data.ptr, @intCast(self.data.len));
    }

    pub fn destructCFDataRef(data: c.CFDataRef) !SerializedData {
        if (data == null) return error.CFDataRefIsNULL;

        return SerializedData{
            .data = @as([*]const u8, c.CFDataGetBytePtr(data))[0..@intCast(c.CFDataGetLength(data))],
        };
    }
};
