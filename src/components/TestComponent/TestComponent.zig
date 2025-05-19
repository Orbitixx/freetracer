const std = @import("std");

const ComponentFramework = @import("../framework/import/index.zig");

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

pub const FilePickerState = struct {
    selected_path: ?[]u8 = null,
    is_selecting: bool = false,
};

const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
const Component = ComponentFramework.Component;
const WorkerStatus = ComponentFramework.WorkerStatus;

pub const ISOFilePickerComponent = struct {
    allocator: std.mem.Allocator,
    appObserver: *const AppObserver,
    state: ComponentState,
    worker: ?ComponentWorker = null,

    pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) ISOFilePickerComponent {
        std.debug.print("\nISOFilePickerComponent: component initialized!", .{});

        return .{
            .allocator = allocator,
            .appObserver = appObserver,
            .state = ComponentState.init(FilePickerState{}),
        };
    }

    fn initWorker(self: *ISOFilePickerComponent) void {
        self.worker = ComponentWorker.init(
            &self.state,
            false,
            ISOFilePickerComponent.workerRun,
            ISOFilePickerComponent.workerCallback,
            self,
        );
    }

    pub fn start(self: *ISOFilePickerComponent) !void {
        std.debug.print("\nISOFilePickerComponent: start() function called!", .{});
        self.initWorker();
    }

    pub fn update(self: *ISOFilePickerComponent) !void {
        // Check for file selection changes
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        self.checkAndJoinWorker();

        _ = state;

        // Update logic
    }

    pub fn draw(self: *ISOFilePickerComponent) !void {
        // Draw file picker UI
        // const state = self.state.getDataLocked();
        // defer self.state.unlock();

        // std.debug.print("\nDrawing file picker UI, selected: {s}", .{if (state.selected_path) |path| path else "none"});

        // Draw UI elements

        _ = self;
    }

    pub fn deinit(self: *ISOFilePickerComponent) void {
        // Clean up resources
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        if (state.selected_path) |path| {
            _ = path;
            // Free the path if it was allocated
        }
    }

    pub fn notify(self: *ISOFilePickerComponent, event: ObserverEvent, payload: ObserverPayload) void {
        self.appObserver.onNotify(event, payload);
    }

    pub fn selectFile(self: *ISOFilePickerComponent) !void {
        if (self.worker) |*worker| {
            try worker.start();
        }
    }

    pub fn checkAndJoinWorker(self: *ISOFilePickerComponent) void {
        if (self.worker) |*worker| {
            if (worker.status == WorkerStatus.NEEDS_JOINING) {
                worker.join();
            }
        }
    }

    // Worker implementation
    fn workerRun(worker: *ComponentWorker) void {
        std.debug.print("\nISOFilePickerComponent: runWorker() started!", .{});

        worker.state.withLock(struct {
            fn lambda(state: *FilePickerState) void {
                state.is_selecting = true;
            }
        }.lambda);

        const data: []u8 = @constCast(&[_]u8{ 0x7B, 0x7C, 0x7C, 0x7B });

        worker.state.withLock(struct {
            fn lambda(state: *FilePickerState) void {
                state.is_selecting = false;
                state.selected_path = data;
            }
        }.lambda);

        std.debug.print("\nISOFilePickerComponent: runWorker() finished executing!", .{});
    }

    fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
        std.debug.print("\nISOFilePickerComponent: workerCallback() called!", .{});

        // const component: *ISOFilePickerComponent = @ptrCast(@alignCast(context));
        _ = worker;
        _ = context;

        std.debug.print("\nISOFilePickerComponent: workerCallback() joined!", .{});
    }

    pub fn asComponent(self: *ISOFilePickerComponent) Component {
        //
        const vtable = &Component.VTable{
            //
            .init_fn = struct {
                fn call(ptr: *anyopaque) anyerror!void {
                    return ISOFilePickerComponent.asInstance(ptr).start();
                }
            }.call,
            .deinit_fn = ISOFilePickerComponent.deinitWrapper,
            .update_fn = ISOFilePickerComponent.updateWrapper,
            .draw_fn = ISOFilePickerComponent.drawWrapper,
            .notify_fn = ISOFilePickerComponent.notifyWrapper,
        };

        return ComponentFramework.Component.init(self, vtable);
    }

    pub fn asInstance(ptr: *anyopaque) *ISOFilePickerComponent {
        return @ptrCast(@alignCast(ptr));
    }

    fn initWrapper(ptr: *anyopaque) anyerror!void {
        return ISOFilePickerComponent.asInstance(ptr).start();
    }

    fn updateWrapper(ptr: *anyopaque) anyerror!void {
        return ISOFilePickerComponent.asInstance(ptr).update();
    }

    fn deinitWrapper(ptr: *anyopaque) void {
        return ISOFilePickerComponent.asInstance(ptr).deinit();
    }

    fn drawWrapper(ptr: *anyopaque) anyerror!void {
        return ISOFilePickerComponent.asInstance(ptr).draw();
    }

    fn notifyWrapper(ptr: *anyopaque, event: ObserverEvent, payload: ObserverPayload) void {
        return ISOFilePickerComponent.asInstance(ptr).notify(event, payload);
    }
};

// Factory function to create instances
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
// pub fn asComponent(component: *ISOFilePickerComponent) Component {
//     return Factory.asComponent(component);
// }
