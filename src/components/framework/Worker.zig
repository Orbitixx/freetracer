const std = @import("std");

const ComponentFramework = @import("./import/index.zig");
const ComponentState = ComponentFramework.ComponentState;
const Component = ComponentFramework.Component;

pub const WorkerStatus = enum(u8) {
    IDLE,
    RUNNING,
    NEEDS_JOINING,
    FINISHED,
};

/// Configuration settings for a Component Worker, which alter its behavior.
pub const WorkerConfig = struct {
    /// Executes worker action on the same thread as the caller (most often the main process thread).
    /// Useful to be able to still use the same Component and Component Worker architecture without
    /// discrete multithreading/worker functionality.
    onSameThreadAsCaller: bool = false,
};

/// A Component Worker object, which dispatches a discrete Component action and,
/// upon completion, calls a specified callback.
pub fn Worker(comptime StateType: type) type {
    return struct {
        const Self = @This();

        const WorkerContext = struct {
            run_fn: *const fn (*Self, context: *anyopaque) void,
            run_context: *anyopaque,
            callback_fn: *const fn (*Self, context: *anyopaque) void,
            callback_context: *anyopaque,
            deinit_fn: ?*const fn (*Self) void = null,
        };

        allocator: std.mem.Allocator,
        state: *ComponentState(StateType),
        context: WorkerContext,
        config: WorkerConfig,
        status: WorkerStatus = .IDLE,
        thread: ?std.Thread = null,

        pub fn init(allocator: std.mem.Allocator, state: *ComponentState(StateType), context: WorkerContext, config: WorkerConfig) Self {
            return .{
                .allocator = allocator,
                .state = state,
                .context = context,
                .config = config,
            };
        }

        pub fn start(self: *Self) !void {
            if (self.status == WorkerStatus.RUNNING) return error.WorkerAlreadyRunning;
            if (self.status == WorkerStatus.NEEDS_JOINING) return error.WorkerThreadNeedsJoining;

            if (!self.config.onSameThreadAsCaller) {
                self.thread = try std.Thread.spawn(
                    .{},
                    Self.threadMain,
                    .{self},
                );
            } else Self.threadMain(self);
        }

        /// Called from another thread, from which the Worker thread was spawned.
        /// Does nothing if called from same thread as the same thread can't join itself.
        pub fn join(self: *Self) void {
            if (self.thread) |thread| {
                thread.join();
            }
            self.thread = null;
            self.status = .FINISHED;
        }

        fn threadMain(self: *Self) void {
            self.status = .RUNNING;
            self.context.run_fn(self, self.context.run_context);
            self.status = .NEEDS_JOINING;
            self.context.callback_fn(self, self.context.callback_context);
        }

        pub fn deinit(self: *Self) void {
            if (self.context.deinit_fn) |deinit_fn| {
                deinit_fn();
            }
        }
    };
}
