const std = @import("std");
const builtin = @import("builtin");
const AppManager = @import("managers/AppManager.zig");

pub fn main() !void {
    var mainAllocator = switch (builtin.mode) {
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => std.heap.DebugAllocator(.{ .thread_safe = true }).init,
        else => std.heap.DebugAllocator(.{ .thread_safe = true }).init,
    };

    const allocator = mainAllocator.allocator();

    defer {
        switch (builtin.mode) {
            .ReleaseSafe, .ReleaseFast, .ReleaseSmall => {
                _ = mainAllocator.detectLeaks();
                _ = mainAllocator.deinit();
            },
            else => {
                _ = mainAllocator.detectLeaks();
                _ = mainAllocator.deinit();
            },
        }
    }

    try AppManager.init(allocator);

    AppManager.startApp() catch |err| {
        std.log.err("\nFreetracer encountered critical error: {any}.\n", .{err});
        return err;
    };
}
