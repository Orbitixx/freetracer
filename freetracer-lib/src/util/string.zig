const std = @import("std");

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
