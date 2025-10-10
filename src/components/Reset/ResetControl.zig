const std = @import("std");
const rl = @import("raylib");

const AppStateMachine = @import("../../managers/AppStateMachine.zig").AppStateMachineSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const Button = @import("../ui/Button.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;

const ResetControl = @This();

allocator: std.mem.Allocator,
component: ?Component = null,
button: Button = undefined,

pub fn init(allocator: std.mem.Allocator) !ResetControl {
    return .{
        .allocator = allocator,
    };
}

pub fn initComponent(self: *ResetControl, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

pub fn start(self: *ResetControl) !void {
    if (self.component == null) try self.initComponent(null);

    self.button = Button.init(
        "Reset",
        null,
        .{ .x = 0, .y = 0 },
        .Primary,
        .{ .context = @ptrCast(self), .function = buttonHandler.call },
        self.allocator,
    );

    try self.button.start();
    self.button.rect.rounded = true;

    const margin_x = WindowManager.relW(0.03);
    const margin_y = WindowManager.relH(0.03);
    const pos = rl.Vector2{
        .x = WindowManager.getWindowWidth() - margin_x - self.button.rect.transform.getWidth(),
        .y = margin_y,
    };
    self.button.setPosition(pos);
}

pub fn update(self: *ResetControl) !void {
    try self.button.update();
}

pub fn draw(self: *ResetControl) !void {
    try self.button.draw();
}

pub fn handleEvent(self: *ResetControl, event: ComponentEvent) !EventResult {
    _ = self;
    _ = event;
    return EventResult.init();
}

pub fn dispatchComponentAction(self: *ResetControl) void {
    _ = self;
}

pub fn deinit(self: *ResetControl) void {
    self.button.deinit();
}

fn triggerReset(self: *ResetControl) void {
    _ = self;
    AppStateMachine.reset();
}

const buttonHandler = struct {
    pub fn call(ctx: *anyopaque) void {
        const self = ResetControl.asInstance(ctx);
        self.triggerReset();
    }
};

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ResetControl);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
