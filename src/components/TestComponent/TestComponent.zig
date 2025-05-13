const std = @import("std");

pub const FilePickerState = struct {
    selected_path: ?[]u8 = null,
    is_selecting: bool = false,
};

const ComponentFramework = @import("../framework/import/index.zig");
const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
const GenericComponent = ComponentFramework.GenericComponent;

// pub const ComponentInstance = ComponentFramework.Component(FilePickerState);
// pub const ComponentWorker = ComponentFramework.Worker(FilePickerState);
// pub const Factory = ComponentFramework.ComponentFactory(FilePickerState);
pub const TestFilePickerComponent = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: ComponentState,
    worker: ?ComponentWorker = null,
    workerNeedsJoining: bool = false,

    // Component-specific function implementations
    pub fn init(allocator: std.mem.Allocator) TestFilePickerComponent {
        // Initialize file picker specific things
        std.debug.print("\nTestFilePickerComponent: component initialized!", .{});

        return .{
            .allocator = allocator,
            .state = ComponentState.init(FilePickerState{}),
        };
    }

    fn initWorker(self: *Self) void {
        self.worker = ComponentWorker.init(
            &self.state,
            TestFilePickerComponent.runWorker,
            TestFilePickerComponent.workerCallback,
            self,
        );
    }

    pub fn start(self: *Self) !void {
        std.debug.print("\nTestFilePickerComponent: start() function called!", .{});

        self.initWorker();
    }

    pub fn update(self: *Self) !void {
        // Check for file selection changes
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        if (self.workerNeedsJoining) {
            self.worker.?.join();
            self.workerNeedsJoining = false;
        }

        _ = state;

        // Update logic
    }

    pub fn draw(self: *Self) !void {
        // Draw file picker UI
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        std.debug.print("\nDrawing file picker UI, selected: {s}", .{if (state.selected_path) |path| path else "none"});

        // Draw UI elements
    }

    pub fn deinit(self: *Self) void {
        // Clean up resources
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        if (state.selected_path) |path| {
            _ = path;
            // Free the path if it was allocated
        }
    }

    pub fn selectFile(self: *Self) !void {
        if (self.worker) |*worker| {
            try worker.start();
        }
    }

    // Worker implementation
    fn runWorker(worker: *ComponentWorker) void {
        std.debug.print("\nTestFilePickerComponent: runWorker() started!", .{});

        worker.state.withLock(struct {
            fn lambda(state: *FilePickerState) void {
                state.is_selecting = true;
            }
        }.lambda);

        const data: []u8 = @constCast(&[_]u8{ 0x7C, 0x7C, 0x7C, 0x7C });

        worker.state.withLock(struct {
            fn lambda(state: *FilePickerState) void {
                state.is_selecting = false;
                state.selected_path = data;
            }
        }.lambda);

        std.debug.print("\nTestFilePickerComponent: runWoker() finished executing!", .{});
    }

    fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
        std.debug.print("\nTestFilePickerComponent: workerCallback() called!", .{});

        const component: *TestFilePickerComponent = @ptrCast(@alignCast(context));
        component.workerNeedsJoining = true;
        _ = worker;

        std.debug.print("\nTestFilePickerComponent: workerCallback() joined!", .{});
    }

    pub fn asGenericComponent(self: *Self) GenericComponent {
        //
        const vtable = &GenericComponent.VTable{
            //
            .init_fn = TestFilePickerComponent.initWrapper,
            .deinit_fn = TestFilePickerComponent.deinitWrapper,
            .update_fn = TestFilePickerComponent.updateWrapper,
            .draw_fn = TestFilePickerComponent.drawWrapper,
        };

        return ComponentFramework.GenericComponent.init(self, vtable);
    }

    fn initWrapper(ptr: *anyopaque) anyerror!void {
        const component: *Self = @ptrCast(@alignCast(ptr));
        return component.start();
    }

    fn updateWrapper(ptr: *anyopaque) anyerror!void {
        const component: *Self = @ptrCast(@alignCast(ptr));
        return component.update();
    }

    fn deinitWrapper(ptr: *anyopaque) void {
        const component: *Self = @ptrCast(@alignCast(ptr));
        component.deinit();
    }

    fn drawWrapper(ptr: *anyopaque) anyerror!void {
        const component: *Self = @ptrCast(@alignCast(ptr));
        return component.draw();
    }
};

// Factory functions to create instances
// pub fn create(allocator: std.mem.Allocator) !struct { component: ComponentInstance, worker: ComponentWorker, state: State } {
//     _ = allocator;
//
//     var state = State.init(FilePickerState{});
//
//     const component = Factory.create(&state, init, deinit, update, draw, null);
//
//     const worker = Factory.createWorker(&state, runWorker);
//
//     return .{
//         .component = component,
//         .worker = worker,
//         .state = state,
//     };
// }
//
// pub fn asGenericComponent(component: *ComponentInstance) ComponentFramework.GenericComponent {
//     return Factory.asGenericComponent(component);
// }
