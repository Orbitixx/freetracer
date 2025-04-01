const std = @import("std");
const assert = std.debug.assert;

/// Attempts to read a buffer as little-endian of specified type
/// buffer type is as defined in std.mem.readInt()
pub fn readLittle(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
    // Ensure T is an integer
    assert(@typeInfo(T) == .int);
    // // Ensure buffer is same number of bytes as desired type
    assert(buffer.len == @sizeOf(T));
    return std.mem.readInt(T, buffer, std.builtin.Endian.little);
}

/// Attempts to read LSB_MSB both-endian buffer as a little-endian integer.
/// The @divExact is dividing bits by 4 instead of 8 because buffer len has to be twice as large as @sizeOf(T)
/// i.e. an [8]u8 LSB_MSB buffer contains an i32 ([4]u8) little-endian while being an i64 both-endian.
pub fn readBoth(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 4)]u8) T {
    // Ensure T is an integer
    assert(@typeInfo(T) == .int);
    // Assert buffer length is even, ensuring little and big symmetry in a both-endian buffer.
    assert(buffer.len % 2 == 0);
    // Assert half of buffer is same number of bytes as T
    assert(buffer.len / 2 == @sizeOf(T));
    return std.mem.readInt(T, buffer[0 .. buffer.len / 2], std.builtin.Endian.little);
}
