const std = @import("std");
const osd = @import("osdialog");
const debug = @import("../../lib/util/debug.zig");

const ComponentFramework = @import("../framework/import/index.zig");

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

pub const FilePickerState = struct {
    selected_path: ?[:0]u8 = null,
    is_selecting: bool = false,
};

const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
const Component = ComponentFramework.Component;

const ComponentEvent = ComponentFramework.Event;
const WorkerStatus = ComponentFramework.WorkerStatus;

pub const ISOFilePickerComponent = struct {
    component: ?Component = null,
    allocator: std.mem.Allocator,
    appObserver: *const AppObserver,
    state: ComponentState,
    worker: ?ComponentWorker = null,

    pub const Events = struct {
        pub const UIWidthChangedEvent = ComponentFramework.defineEvent("iso_file_picker.ui_width_changed", struct { newWidth: f32 });
    };

    pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) ISOFilePickerComponent {
        std.debug.print("\nISOFilePickerComponent: component initialized!", .{});

        return .{
            .allocator = allocator,
            .appObserver = appObserver,
            .state = ComponentState.init(FilePickerState{}),
        };
    }

    fn initComponent(self: *ISOFilePickerComponent) void {
        const vtable = &Component.VTable{
            .start_fn = ISOFilePickerComponent.startWrapper,
            .deinit_fn = ISOFilePickerComponent.deinitWrapper,
            .update_fn = ISOFilePickerComponent.updateWrapper,
            .draw_fn = ISOFilePickerComponent.drawWrapper,
            .handle_event_fn = ISOFilePickerComponent.handleEventWrapper,
        };

        self.component = ComponentFramework.Component.init(self, vtable);
    }

    fn initWorker(self: *ISOFilePickerComponent) void {
        self.worker = ComponentWorker.init(
            self.allocator,
            &self.state,
            .{
                .run_fn = ISOFilePickerComponent.workerRun,
                .run_context = self,
                .callback_fn = ISOFilePickerComponent.workerCallback,
                .callback_context = self,
            },
            .{
                .onSameThreadAsCaller = true,
            },
        );
    }

    pub fn start(self: *ISOFilePickerComponent) !void {
        std.debug.print("\nISOFilePickerComponent: start() function called!", .{});
        if (self.component == null) self.initComponent();
        if (self.worker == null) self.initWorker();
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

    pub fn handleEvent(self: *ISOFilePickerComponent, event: ComponentEvent) !void {
        _ = self;
        debug.printf("\nISOFilePickerComponent: handleEvent() received an event: {any}", .{event.name});

        switch (event.hash) {
            Events.UIWidthChangedEvent.Hash => {
                // TODO: handle null data gracefully
                const data = Events.UIWidthChangedEvent.getData(&event).?;
                debug.printf("\nISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newWidth = {d}", .{ event.name, data.newWidth });
            },
            else => {},
        }
    }

    pub fn deinit(self: *ISOFilePickerComponent) void {
        // Clean up resources
        const state = self.state.getDataLocked();
        defer self.state.unlock();

        if (state.selected_path) |path| {
            self.allocator.free(path);
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

    pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
        std.debug.print("\nISOFilePickerComponent: runWorker() started!", .{});

        _ = context;

        worker.state.withLock(struct {
            fn lambda(state: *FilePickerState) void {
                state.is_selecting = true;
            }
        }.lambda);

        worker.state.lock();
        defer worker.state.unlock();

        worker.state.data.selected_path = osd.path(worker.allocator, .open, .{});
        worker.state.data.is_selecting = false;

        std.debug.print("\nISOFilePickerComponent: runWorker() finished executing!", .{});
    }

    pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
        std.debug.print("\nISOFilePickerComponent: workerCallback() called!", .{});

        _ = worker;
        _ = context;

        std.debug.print("\nISOFilePickerComponent: workerCallback() joined!", .{});
    }

    pub fn asComponent(self: *ISOFilePickerComponent) *Component {
        if (self.component == null) self.initComponent();
        return &self.component.?;
    }

    pub fn asInstance(ptr: *anyopaque) *ISOFilePickerComponent {
        return @ptrCast(@alignCast(ptr));
    }

    fn startWrapper(ptr: *anyopaque) anyerror!void {
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

    fn handleEventWrapper(ptr: *anyopaque, event: ComponentFramework.Event) anyerror!void {
        return ISOFilePickerComponent.asInstance(ptr).handleEvent(event);
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
