const std = @import("std");

const ComponentFramework = @import("./import/index.zig");
const ComponentState = ComponentFramework.ComponentState;
const GenericComponent = ComponentFramework.GenericComponent;

pub fn Worker(comptime StateType: type) type {
    return struct {
        const Self = @This();

        state: *ComponentState(StateType),
        thread: ?std.Thread = null,
        run_fn: *const fn (*Self) void,
        callback_fn: ?*const fn (*Self) void = null,
        running: bool = false,

        pub fn init(state: *ComponentState(StateType), run_fn: *const fn (*Self) void, callback_fn: ?*const fn (*Self) void) Self {
            return .{
                .state = state,
                .run_fn = run_fn,
                .callback_fn = callback_fn orelse null,
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
            if (self.callback_fn) |callback| callback(self);
        }
    };
}
