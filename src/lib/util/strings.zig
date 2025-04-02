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
