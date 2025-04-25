const std = @import("std");
const debug = @import("../../src/lib/util/debug.zig");

pub fn main() !void {
    debug.printf("All your {s} are belong to us.\n", .{"codebase"});
}
