const std = @import("std");

const ComponentState = @import("./import/index.zig").ComponentState;

pub fn Worker(comptime StateType: type) type {
    return struct {
        const Self = @This();

        state: *ComponentState(StateType),
        thread: ?std.Thread = null,
        run_fn: fn (*Self) void,
        running: bool = false,

        pub fn init(state: *ComponentState(StateType), run_fn: fn (*Self) void) Self {
            return .{
                .state = state,
                .run_fn = run_fn,
            };
        }

        pub fn start(self: *Self) !void {
            if (self.running) return error.WorkerAlreadyRunning;

            self.running = true;
            self.thread = try std.Thread.spawn(.{}, Self.threadMain, .{self});
        }

        pub fn join(self: *Self) !void {
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
                self.running = false;
            }
        }

        fn threadMain(self: *Self) void {
            self.run_fn(self);
        }
    };
}
