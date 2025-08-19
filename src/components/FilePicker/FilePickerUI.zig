const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const AppConfig = @import("../../config.zig");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.ISO_FILE_PICKER_UI;

const ISOFilePicker = @import("./FilePicker.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Rectangle = UIFramework.Primitives.Rectangle;
const Transform = UIFramework.Primitives.Transform;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;

const Styles = UIFramework.Styles;
const Color = Styles.Color;

pub const ISOFilePickerUIState = struct {
    isActive: bool = true,
    isoPath: ?[:0]u8 = null,
};
pub const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);

const ISOFilePickerUI = @This();

// Component-agnostic props
state: ComponentState,
parent: *ISOFilePicker,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
bgRect: Rectangle = undefined,
headerLabel: Text = undefined,
diskImg: Texture = undefined,
button: Button = undefined,
isoTitle: Text = undefined,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    pub const onISOFilePathChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "iso_file_path_changed"),
        struct { newPath: [:0]u8 },
        struct {},
    );

    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    pub const onGetUIDimensions = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "get_ui_width"),
        struct { transform: Transform },
        struct {},
    );

    pub const onUIDimensionsQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "get_ui"),
        struct {},
        struct { bgRectWidth: f32 },
    );
};

pub fn init(allocator: std.mem.Allocator, parent: *ISOFilePicker) !ISOFilePickerUI {
    Debug.log(.DEBUG, "ISOFilePickerUI: start() called.", .{});

    return ISOFilePickerUI{
        .allocator = allocator,
        .state = ComponentState.init(ISOFilePickerUIState{}),
        .parent = parent,
    };
}

pub fn initComponent(self: *ISOFilePickerUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *ISOFilePickerUI) !void {
    Debug.log(.DEBUG, "ISOFilePickerUI: component start() called.", .{});

    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;

    self.bgRect = Rectangle{
        .transform = .{
            .x = winRelX(0.08),
            .y = winRelY(0.2),
            .w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
            .h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        },
        .style = .{
            .color = Color.violet,
            .borderStyle = .{
                .color = Color.white,
            },
        },
        .rounded = true,
        .bordered = true,
    };

    self.headerLabel = Text.init("image", .{
        .x = self.bgRect.transform.x + 12,
        .y = self.bgRect.transform.relY(0.01),
    }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Color.white,
    });

    self.diskImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.diskImg.transform.x = self.bgRect.transform.relX(0.5) - self.diskImg.transform.w / 2;
    self.diskImg.transform.y = self.bgRect.transform.relY(0.5) - self.diskImg.transform.h / 2;
    self.diskImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    self.button = Button.init(
        "SELECT ISO",
        self.bgRect.transform.getPosition(),
        .Primary,
        .{
            .context = self.parent,
            .function = ISOFilePicker.dispatchComponentActionWrapper.call,
        },
    );

    try self.button.start();

    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.w, 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.h, 2),
    });

    self.button.rect.rounded = true;

    self.isoTitle = Text.init("No ISO selected...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

    Debug.log(.DEBUG, "ISOFilePickerUI: component start() finished.", .{});
}

pub fn handleEvent(self: *ISOFilePickerUI, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "ISOFilePickerUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {
        //
        Events.onISOFilePathChanged.Hash => {
            //
            const data = Events.onISOFilePathChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(.SUCCESS);

            var newName: [:0]const u8 = @ptrCast("No ISO selected...");

            if (data.newPath.len > 0) {
                //
                {
                    self.state.lock();
                    defer self.state.unlock();
                    self.state.data.isoPath = data.newPath;
                }

                var lastSlash: usize = 0;

                for (0..data.newPath.len) |i| {
                    // Find the last forward slash in the path (0x2f)
                    if (data.newPath[i] == 0x2f) lastSlash = i;
                }

                newName = data.newPath[lastSlash + 1 .. data.newPath.len :0];
            }

            self.isoTitle = Text.init(newName, .{
                .x = self.bgRect.transform.relX(0.5),
                .y = self.bgRect.transform.relY(0.5),
            }, .{
                .fontSize = 14,
            });
        },

        // NOTE: Deprecated implementation. Use Events.onUIDimensionsQueried.
        // ISOFilePickerUI emits this event in response to receiving the same event
        Events.onGetUIDimensions.Hash => {
            //
            const data = Events.onGetUIDimensions.Data{ .transform = self.bgRect.transform };
            const responseEvent = Events.onGetUIDimensions.create(self.asComponentPtr(), &data);
            EventManager.broadcast(responseEvent);
            eventResult.validate(.SUCCESS);
        },

        Events.onUIDimensionsQueried.Hash => {
            eventResult.validate(.SUCCESS);

            const responseDataPtr: *Events.onUIDimensionsQueried.Response = try self.allocator.create(Events.onUIDimensionsQueried.Response);
            responseDataPtr.* = .{ .bgRectWidth = self.bgRect.transform.w };
            eventResult.data = @ptrCast(@alignCast(responseDataPtr));
        },

        ISOFilePicker.Events.onActiveStateChanged.Hash => {
            //
            const data = ISOFilePicker.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(.SUCCESS);

            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            switch (data.isActive) {
                true => {
                    self.headerLabel.style.textColor = Color.white;
                    self.diskImg.transform.scale = 1.0;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.violet,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    self.headerLabel.style.textColor = Color.offWhite;
                    self.diskImg.transform.scale = 0.7;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                        .color = Color.darkViolet,
                        .borderColor = Color.transparentDark,
                    });
                },
            }

            const responseEvent = Events.onGetUIDimensions.create(
                self.asComponentPtr(),
                &.{ .transform = self.bgRect.transform },
            );

            EventManager.broadcast(responseEvent);
        },

        else => {},
    }

    return eventResult;
}

fn recalculateUI(self: *ISOFilePickerUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "IsoFilePickerUI: recalculating UI...", .{});

    self.bgRect.transform.w = bgRectParams.width;
    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    self.diskImg.transform.x = self.bgRect.transform.relX(0.5) - self.diskImg.transform.getWidth() / 2;
    self.diskImg.transform.y = self.bgRect.transform.relY(0.5) - self.diskImg.transform.getHeight() / 2;

    self.isoTitle.transform.x = self.bgRect.transform.relX(0.5) - self.isoTitle.getDimensions().width / 2;
    self.isoTitle.transform.y = self.diskImg.transform.y + self.diskImg.transform.getHeight() + winRelY(0.02);

    self.button.setPosition(.{ .x = self.bgRect.transform.relX(0.5) - self.button.rect.transform.getWidth() / 2, .y = self.button.rect.transform.y });
}

pub fn update(self: *ISOFilePickerUI) !void {
    try self.button.update();
}

pub fn draw(self: *ISOFilePickerUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    self.bgRect.draw();
    self.headerLabel.draw();
    self.diskImg.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *ISOFilePickerUI) !void {
    try self.button.draw();
}

fn drawInactive(self: *ISOFilePickerUI) !void {
    self.isoTitle.draw();
}

pub fn deinit(self: *ISOFilePickerUI) void {
    if (self.state.data.isoPath) |isoPath| {
        self.parent.allocator.free(isoPath);
    }
}

pub fn dispatchComponentAction(self: *ISOFilePickerUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
