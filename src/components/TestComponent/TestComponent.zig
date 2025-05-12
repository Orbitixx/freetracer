const std = @import("std");

pub const FilePickerState = struct {
    selected_path: ?[]u8 = null,
    is_selecting: bool = false,
};

const ComponentFramework = @import("../framework/import/index.zig");
const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
// const GenericComponent = ComponentFramework.GenericComponent;

// pub const ComponentInstance = ComponentFramework.Component(FilePickerState);
// pub const ComponentWorker = ComponentFramework.Worker(FilePickerState);
// pub const Factory = ComponentFramework.ComponentFactory(FilePickerState);
pub const GenericComponent = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: ComponentState,
    worker: ?ComponentWorker = null,

    // Component-specific function implementations
    pub fn init(allocator: std.mem.Allocator) Self {
        // Initialize file picker specific things
        std.debug.print("FilePicker initialized\n", .{});

        var componentInstance: Self = .{
            .allocator = allocator,
            .state = ComponentState.init(FilePickerState{}),
        };

        componentInstance.worker = ComponentWorker.init(&componentInstance.state, Self.runWorker);

        return componentInstance;
    }

    pub fn update(self: *Self) !void {
        // Check for file selection changes
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        _ = state;

        // Update logic
    }

    pub fn draw(self: *Self) !void {
        // Draw file picker UI
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        std.debug.print("Drawing file picker UI, selected: {s}\n", .{if (state.selected_path) |path| path else "none"});

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
        // Do background file system operations
        worker.state.withLock(struct {
            fn callback(state: *FilePickerState) void {
                state.is_selecting = true;
            }
        }.callback);

        // Do work...
        std.time.sleep(1_000_000_000); // Simulate work

        worker.state.withLock(struct {
            fn callback(state: *FilePickerState) void {
                state.is_selecting = false;
                // Set selected path
            }
        }.callback);

        std.debug.print("\nNewWorker finished!");
    }

    pub fn asGenericComponent(self: *Self) GenericComponent {
        //
        const vtable = &GenericComponent.VTable{
            //
            .init_fn = struct {
                fn wrapper(ptr: *anyopaque) anyerror!void {
                    // No initialization needed
                    _ = ptr;
                    return;
                }
            }.wrapper,

            .deinit_fn = struct {
                fn wrapper(ptr: *anyopaque) void {
                    const component: *Self = @ptrCast(@alignCast(ptr));
                    component.deinit();
                }
            }.wrapper,

            .update_fn = struct {
                fn wrapper(ptr: *anyopaque) anyerror!void {
                    const component: *Self = @ptrCast(@alignCast(ptr));
                    return component.update();
                }
            }.wrapper,

            .draw_fn = struct {
                fn wrapper(ptr: *anyopaque) anyerror!void {
                    const component: *Self = @ptrCast(@alignCast(ptr));
                    return component.draw();
                }
            }.wrapper,
        };

        return ComponentFramework.GenericComponent.init(self, vtable);
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
