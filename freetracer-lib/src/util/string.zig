const std = @import("std");
const Character = @import("../constants.zig").Character;

pub fn parseUpToDelimeter(comptime length: comptime_int, data: [length]u8, delimeter: u8) [length]u8 {
    var stringArray: [length]u8 = std.mem.zeroes([length]u8);

    for (data, 0..data.len) |char, i| {
        if (char == delimeter) break;
        stringArray[i] = data[i];
    }

    return stringArray;
}

pub fn parseAfterDelimeter(comptime length: comptime_int, data: [length]u8, delimeter: u8, terminator: u8) [length]u8 {
    var stringArray: [length]u8 = std.mem.zeroes([length]u8);
    var delimeterIndex: usize = 0;

    for (data, 0..data.len) |char, i| {
        if (i >= delimeterIndex) if (char == terminator) break;
        if (char == delimeter) delimeterIndex = i;
        if (delimeterIndex > 0 and i > delimeterIndex) stringArray[i - delimeterIndex - 1] = char;
    }

    return stringArray;
}

pub fn sanitizeString(buf: []u8, input: []const u8) []const u8 {
    var len: usize = 0;

    for (input) |char| {
        if (len >= buf.len - 1) break;
        // Allow printable ASCII characters, replace others
        if (char >= 32 and char <= 126) {
            buf[len] = char;
        } else {
            buf[len] = '.';
        }

        len += 1;
    }

    return buf[0..len];
}

pub fn concatStrings(comptime len: usize, buf: *[len]u8, str1: []const u8, str2: []const u8) ![:0]u8 {
    const required = str1.len + str2.len;
    if (required >= len) return error.ConcatStringLengthExceedsBufferSize;

    @memcpy(buf.*[0..str1.len], str1);
    @memcpy(buf.*[str1.len..required], str2);
    buf.*[required] = Character.NULL;

    return buf.*[0..required :0];
}
