const std = @import("std");
const testing = std.testing;

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

// -- Tests --

// A simple state for our tests.
const TestState = struct {
    run_count: u32 = 0,
    callback_count: u32 = 0,
    deinit_count: u32 = 0,
};

// This function will be executed by the worker.
fn testRunFn(worker: *Worker(TestState), context: *anyopaque) void {
    _ = worker;
    const test_state: *TestState = @ptrCast(@alignCast(context));
    test_state.run_count += 1;
}

// This function will be called after the worker's main function completes.
fn testCallbackFn(worker: *Worker(TestState), context: *anyopaque) void {
    _ = worker;
    const test_state: *TestState = @ptrCast(@alignCast(context));
    test_state.callback_count += 1;
}

// This function is called when the worker is deinitialized.
fn testDeinitFn(worker: *Worker(TestState)) void {
    const test_state: *TestState = @ptrCast(@alignCast(worker.context.run_context));
    test_state.deinit_count += 1;
}

test "worker runs on the same thread" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var component_state = ComponentFramework.ComponentState(TestState){ ._state = .{} };
    var test_state = TestState{};

    const context = Worker(TestState).WorkerContext{
        .run_fn = testRunFn,
        .run_context = &test_state,
        .callback_fn = testCallbackFn,
        .callback_context = &test_state,
        .deinit_fn = testDeinitFn,
    };

    // Configure the worker to run on the same thread as the caller.
    const config = WorkerConfig{ .onSameThreadAsCaller = true };

    var worker = Worker(TestState).init(allocator, &component_state, context, config);
    defer worker.deinit();

    try testing.expectEqual(worker.status, WorkerStatus.IDLE);

    try worker.start();

    // When running on the same thread, the status should immediately be NEEDS_JOINING
    // because the run and callback functions have already executed synchronously.
    try testing.expectEqual(worker.status, WorkerStatus.NEEDS_JOINING);
    try testing.expectEqual(@as(u32, 1), test_state.run_count);
    try testing.expectEqual(@as(u32, 1), test_state.callback_count);

    // Joining should finalize the state.
    worker.join();
    try testing.expectEqual(worker.status, WorkerStatus.FINISHED);

    // Deinit should be called.
    worker.deinit();
    try testing.expectEqual(@as(u32, 1), test_state.deinit_count);
}

test "worker runs on a different thread" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var component_state = ComponentFramework.ComponentState(TestState){ ._state = .{} };

    // Use an atomic value to safely track state changes across threads.
    var test_state = struct {
        run_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        callback_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    }{};

    const thread_run_fn = struct {
        fn f(worker: *Worker(TestState), context: *anyopaque) void {
            _ = worker;
            const state: *@TypeOf(test_state) = @ptrCast(@alignCast(context));
            _ = state.run_count.fetchAdd(1, .SeqCst);
            // Simulate some work
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }.f;

    const thread_callback_fn = struct {
        fn f(worker: *Worker(TestState), context: *anyopaque) void {
            _ = worker;
            const state: *@TypeOf(test_state) = @ptrCast(@alignCast(context));
            _ = state.callback_count.fetchAdd(1, .SeqCst);
        }
    }.f;

    const context = Worker(TestState).WorkerContext{
        .run_fn = thread_run_fn,
        .run_context = &test_state,
        .callback_fn = thread_callback_fn,
        .callback_context = &test_state,
    };

    // Default config is onSameThreadAsCaller = false
    const config = WorkerConfig{};
    var worker = Worker(TestState).init(allocator, &component_state, context, config);

    try worker.start();

    // The worker should be running in the background.
    try testing.expectEqual(worker.status, WorkerStatus.RUNNING);

    // Wait for the worker to finish its job and call the callback.
    while (worker.status != .NEEDS_JOINING) {
        std.time.sleep(1 * std.time.ns_per_ms);
    }

    try testing.expectEqual(@as(u32, 1), test_state.run_count.load(.SeqCst));
    try testing.expectEqual(@as(u32, 1), test_state.callback_count.load(.SeqCst));

    worker.join();
    try testing.expectEqual(worker.status, WorkerStatus.FINISHED);
}

test "start worker that is already running" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var component_state = ComponentFramework.ComponentState(TestState){ ._state = .{} };
    var test_state = TestState{};

    const context = Worker(TestState).WorkerContext{
        .run_fn = testRunFn,
        .run_context = &test_state,
        .callback_fn = testCallbackFn,
        .callback_context = &test_state,
    };

    const config = WorkerConfig{ .onSameThreadAsCaller = true };
    var worker = Worker(TestState).init(allocator, &component_state, context, config);
    defer worker.deinit();

    try worker.start();
    // Trying to start it again should result in an error.
    const err = worker.start();
    try testing.expectError(error.WorkerThreadNeedsJoining, err);
}
