const std = @import("std");
const assert = std.debug.assert;

pub fn eql(str1: []const u8, str2: []const u8) bool {
    if (str1.len != str2.len) return false;
    assert(str1.len == str2.len);

    for (str1, str2) |i, j| {
        if (i != j) return false;
    }

    return true;
}

pub fn truncToNull(string: []u8) []u8 {
    var nullPosition: u32 = 0;

    for (0..string.len) |i| {
        if (string[i] != 0x00) continue;

        nullPosition = @intCast(i);
        break;
    }

    if (nullPosition == 0) return string;

    return string[0..nullPosition];
}
