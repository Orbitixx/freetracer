const std = @import("std");
const builtin = @import("builtin");
const env = @import("../env.zig");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;
const time = freetracer_lib.time;

const XPCService = freetracer_lib.Mach.XPCService;
const DebugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true });

pub const ShutdownManagerSingleton = struct {
    var instance: ?ShutdownManager = null;

    const ShutdownManager = struct {
        allocator: *DebugAllocator,
        xpcService: *XPCService,
    };

    pub fn init(allocator: *DebugAllocator, xpcService: *XPCService) void {
        instance = ShutdownManager{
            .allocator = allocator,
            .xpcService = xpcService,
        };
    }

    pub fn exitFunction(context: ?*anyopaque) callconv(.c) void {
        // Do not need to use context since this is a singleton instance accessible globally
        _ = context;

        if (instance) |inst| {
            inst.xpcService.deinit();
            Debug.deinit();

            switch (builtin.mode) {
                .ReleaseFast, .ReleaseSafe, .ReleaseSmall => {
                    _ = inst.allocator.detectLeaks();
                    _ = inst.allocator.deinit();
                },
                else => {
                    _ = inst.allocator.detectLeaks();
                    _ = inst.allocator.deinit();
                },
            }
        } else {
            Debug.log(.ERROR, "ShutdownManager.exitFunction() called prior to instance being initialized!", .{});
            Debug.deinit();
        }

        std.process.exit(0);
    }

    pub fn exitSuccessfully() void {
        Debug.log(.INFO, "Freetracer Helper successfully finished executing.", .{});

        // const delay = xpc.dispatch_time(xpc.DISPATCH_TIME_NOW, 500_000_000);
        // xpc.dispatch_after_f(delay, xpc.dispatch_get_main_queue(), null, &exitFunction);

        std.Thread.sleep(500_000_000);
        xpc.dispatch_async_f(xpc.dispatch_get_main_queue(), null, &exitFunction);
    }

    pub fn terminateWithError(err: anyerror) void {
        Debug.log(.ERROR, "Freetracer Helper terminated with error code: {any}", .{err});
        xpc.dispatch_async_f(xpc.dispatch_get_main_queue(), null, &exitFunction);
    }
};
