const std = @import("std");
const AppManager = @import("managers/AppManager.zig");

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    defer {
        _ = debugAllocator.detectLeaks();
        _ = debugAllocator.deinit();
    }

    var app = AppManager.init(allocator);
    try app.run();
}
