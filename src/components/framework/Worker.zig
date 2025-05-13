const std = @import("std");

const ComponentFramework = @import("./import/index.zig");
const ComponentState = ComponentFramework.ComponentState;
const GenericComponent = ComponentFramework.GenericComponent;

pub const WorkerStatus = enum(u8) {
    IDLE,
    RUNNING,
    NEEDS_JOINING,
    FINISHED,
};

pub fn Worker(comptime StateType: type) type {
    return struct {
        const Self = @This();

        state: *ComponentState(StateType),
        status: WorkerStatus = .IDLE,
        isOnSeparateThread: bool = true,
        thread: ?std.Thread = null,
        run_fn: *const fn (*Self) void,
        callback_fn: *const fn (*Self, ctx: *anyopaque) void,
        callback_ctx: *anyopaque,
        running: bool = false,

        pub fn init(state: *ComponentState(StateType), isOnSeparateThread: bool, run_fn: *const fn (*Self) void, callback_fn: *const fn (*Self, ctx: *anyopaque) void, callback_ctx: *anyopaque) Self {
            return .{
                .state = state,
                .run_fn = run_fn,
                .callback_fn = callback_fn,
                .callback_ctx = callback_ctx,
                .isOnSeparateThread = isOnSeparateThread,
            };
        }

        pub fn start(self: *Self) !void {
            if (self.status == WorkerStatus.RUNNING) return error.WorkerAlreadyRunning;
            if (self.status == WorkerStatus.NEEDS_JOINING) return error.WorkerThreadNeedsJoining;

            if (self.isOnSeparateThread) self.thread = try std.Thread.spawn(.{}, Self.threadMain, .{self}) else Self.threadMain(self);
        }

        pub fn join(self: *Self) void {
            if (self.thread) |thread| {
                thread.join();
            }
            self.thread = null;
            self.status = .FINISHED;
        }

        fn threadMain(self: *Self) void {
            self.status = .RUNNING;
            self.run_fn(self);
            self.status = .NEEDS_JOINING;
            self.callback_fn(self, self.callback_ctx);
        }
    };
}
