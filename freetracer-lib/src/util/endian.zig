const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

/// Attempts to read a buffer as little-endian of specified type
/// buffer type is as defined in std.mem.readInt()
pub fn readLittle(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
    // Ensure T is an integer
    assert(@typeInfo(T) == .int);
    // // Ensure buffer is same number of bytes as desired type
    assert(buffer.len == @sizeOf(T));
    return std.mem.readInt(T, buffer, std.builtin.Endian.little);
}

/// Attempts to read a buffer as big-endian of specified type
/// buffer type is as defined in std.mem.readInt()
pub fn readBig(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
    // Ensure T is an integer
    assert(@typeInfo(T) == .int);
    // // Ensure buffer is same number of bytes as desired type
    assert(buffer.len == @sizeOf(T));
    return std.mem.readInt(T, buffer, std.builtin.Endian.big);
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

// Tests for readLittle
test "readLittle u8" {
    const buffer: [1]u8 = .{0x42};
    const result = readLittle(u8, &buffer);
    try testing.expectEqual(@as(u8, 0x42), result);
}

test "readLittle i8" {
    const buffer: [1]u8 = .{0xFF}; // -1 in two's complement
    const result = readLittle(i8, &buffer);
    try testing.expectEqual(@as(i8, -1), result);
}

test "readLittle u16" {
    const buffer: [2]u8 = .{ 0x34, 0x12 }; // Little-endian: 0x1234
    const result = readLittle(u16, &buffer);
    try testing.expectEqual(@as(u16, 0x1234), result);
}

test "readLittle i16" {
    const buffer: [2]u8 = .{ 0xFF, 0xFF }; // -1 in two's complement
    const result = readLittle(i16, &buffer);
    try testing.expectEqual(@as(i16, -1), result);
}

test "readLittle u32" {
    const buffer: [4]u8 = .{ 0x78, 0x56, 0x34, 0x12 }; // Little-endian: 0x12345678
    const result = readLittle(u32, &buffer);
    try testing.expectEqual(@as(u32, 0x12345678), result);
}

test "readLittle i32" {
    const buffer: [4]u8 = .{ 0x00, 0x00, 0x00, 0x80 }; // Little-endian: INT32_MIN
    const result = readLittle(i32, &buffer);
    try testing.expectEqual(@as(i32, std.math.minInt(i32)), result);
}

test "readLittle u64" {
    const buffer: [8]u8 = .{ 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01 };
    const result = readLittle(u64, &buffer);
    try testing.expectEqual(@as(u64, 0x0123456789ABCDEF), result);
}

test "readLittle i64" {
    const buffer: [8]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }; // Little-endian: INT64_MAX
    const result = readLittle(i64, &buffer);
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), result);
}

// Tests for readBig
test "readBig u8" {
    const buffer: [1]u8 = .{0x42};
    const result = readBig(u8, &buffer);
    try testing.expectEqual(@as(u8, 0x42), result);
}

test "readBig i8" {
    const buffer: [1]u8 = .{0xFF}; // -1 in two's complement
    const result = readBig(i8, &buffer);
    try testing.expectEqual(@as(i8, -1), result);
}

test "readBig u16" {
    const buffer: [2]u8 = .{ 0x12, 0x34 }; // Big-endian: 0x1234
    const result = readBig(u16, &buffer);
    try testing.expectEqual(@as(u16, 0x1234), result);
}

test "readBig i16" {
    const buffer: [2]u8 = .{ 0xFF, 0xFF }; // -1 in two's complement
    const result = readBig(i16, &buffer);
    try testing.expectEqual(@as(i16, -1), result);
}

test "readBig u32" {
    const buffer: [4]u8 = .{ 0x12, 0x34, 0x56, 0x78 }; // Big-endian: 0x12345678
    const result = readBig(u32, &buffer);
    try testing.expectEqual(@as(u32, 0x12345678), result);
}

test "readBig i32" {
    const buffer: [4]u8 = .{ 0x80, 0x00, 0x00, 0x00 }; // Big-endian: INT32_MIN
    const result = readBig(i32, &buffer);
    try testing.expectEqual(@as(i32, std.math.minInt(i32)), result);
}

test "readBig u64" {
    const buffer: [8]u8 = .{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF };
    const result = readBig(u64, &buffer);
    try testing.expectEqual(@as(u64, 0x0123456789ABCDEF), result);
}

test "readBig i64" {
    const buffer: [8]u8 = .{ 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }; // Big-endian: INT64_MAX
    const result = readBig(i64, &buffer);
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), result);
}

// Tests for readBoth
test "readBoth u8" {
    // For u8, buffer needs to be [2]u8 (bits/4 = 8/4 = 2)
    const buffer: [2]u8 = .{ 0x42, 0x00 }; // LSB part contains the value
    const result = readBoth(u8, &buffer);
    try testing.expectEqual(@as(u8, 0x42), result);
}

test "readBoth i8" {
    const buffer: [2]u8 = .{ 0xFF, 0x00 }; // LSB part contains -1
    const result = readBoth(i8, &buffer);
    try testing.expectEqual(@as(i8, -1), result);
}

test "readBoth u16" {
    // For u16, buffer needs to be [4]u8 (bits/4 = 16/4 = 4)
    const buffer: [4]u8 = .{ 0x34, 0x12, 0x00, 0x00 }; // LSB part: little-endian 0x1234
    const result = readBoth(u16, &buffer);
    try testing.expectEqual(@as(u16, 0x1234), result);
}

test "readBoth i16" {
    const buffer: [4]u8 = .{ 0xFF, 0xFF, 0x00, 0x00 }; // LSB part: -1
    const result = readBoth(i16, &buffer);
    try testing.expectEqual(@as(i16, -1), result);
}

test "readBoth u32" {
    // For u32, buffer needs to be [8]u8 (bits/4 = 32/4 = 8)
    const buffer: [8]u8 = .{ 0x78, 0x56, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00 }; // LSB part: little-endian 0x12345678
    const result = readBoth(u32, &buffer);
    try testing.expectEqual(@as(u32, 0x12345678), result);
}

test "readBoth i32" {
    const buffer: [8]u8 = .{ 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00 }; // LSB part: INT32_MIN
    const result = readBoth(i32, &buffer);
    try testing.expectEqual(@as(i32, std.math.minInt(i32)), result);
}

test "readBoth u64" {
    // For u64, buffer needs to be [16]u8 (bits/4 = 64/4 = 16)
    const buffer: [16]u8 = .{
        0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, // LSB part
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // MSB part (ignored)
    };
    const result = readBoth(u64, &buffer);
    try testing.expectEqual(@as(u64, 0x0123456789ABCDEF), result);
}

test "readBoth i64" {
    const buffer: [16]u8 = .{
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, // LSB part: INT64_MAX
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // MSB part (ignored)
    };
    const result = readBoth(i64, &buffer);
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), result);
}

// Edge case tests
test "readLittle zero value" {
    const buffer: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
    const result = readLittle(u32, &buffer);
    try testing.expectEqual(@as(u32, 0), result);
}

test "readBig zero value" {
    const buffer: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
    const result = readBig(u32, &buffer);
    try testing.expectEqual(@as(u32, 0), result);
}

test "readBoth zero value" {
    const buffer: [8]u8 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const result = readBoth(u32, &buffer);
    try testing.expectEqual(@as(u32, 0), result);
}

test "readLittle max unsigned value" {
    const buffer: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF };
    const result = readLittle(u32, &buffer);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), result);
}

test "readBig max unsigned value" {
    const buffer: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF };
    const result = readBig(u32, &buffer);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), result);
}

test "readBoth max unsigned value" {
    const buffer: [8]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00 };
    const result = readBoth(u32, &buffer);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), result);
}

// Test to verify endianness differences
test "endianness difference between readLittle and readBig" {
    const buffer: [2]u8 = .{ 0x01, 0x02 };
    const little_result = readLittle(u16, &buffer);
    const big_result = readBig(u16, &buffer);
    try testing.expectEqual(@as(u16, 0x0201), little_result); // Little-endian: LSB first
    try testing.expectEqual(@as(u16, 0x0102), big_result); // Big-endian: MSB first
    try testing.expect(little_result != big_result);
}
