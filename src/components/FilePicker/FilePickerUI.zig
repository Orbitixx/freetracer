const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const AppConfig = @import("../../config.zig");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

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
bgRect: ?Rectangle = null,
headerLabel: ?Text = null,
diskImg: ?Texture = null,
button: ?Button = null,
isoTitle: ?Text = null,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    pub const onISOFilePathChanged = ComponentFramework.defineEvent(
        "iso_file_picker_ui.iso_file_path_changed",
        struct { newPath: [:0]u8 },
        struct {},
    );

    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        "iso_file_picker_ui.active_state_changed",
        struct { isActive: bool },
        struct {},
    );

    pub const onGetUIDimensions = ComponentFramework.defineEvent(
        "iso_file_picker_ui.get_ui_width",
        struct { transform: Transform },
        struct {},
    );

    pub const onUIDimensionsQueried = ComponentFramework.defineEvent(
        "iso_file_picker_ui.get_ui",
        struct {},
        struct {
            bgRectWidth: f32,
        },
    );
};

pub fn init(allocator: std.mem.Allocator, parent: *ISOFilePicker) !ISOFilePickerUI {
    debug.print("\nISOFilePickerUI: start() called.");

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
    debug.print("\nISOFilePickerUI: component start() called.");

    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe("iso_file_picker_ui", component)) return error.UnableToSubscribeToEventManager;
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

    if (self.bgRect) |bgRect| {
        self.button = Button.init(
            "SELECT ISO",
            bgRect.transform.getPosition(),
            .Primary,
            .{
                .context = self.parent,
                .function = ISOFilePicker.dispatchComponentActionWrapper.call,
            },
        );

        self.headerLabel = Text.init("image", .{
            .x = bgRect.transform.x + 12,
            .y = bgRect.transform.relY(0.01),
        }, .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Color.white,
        });

        self.diskImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });

        if (self.diskImg) |*img| {
            img.transform.x = bgRect.transform.relX(0.5) - img.transform.w / 2;
            img.transform.y = bgRect.transform.relY(0.5) - img.transform.h / 2;
            img.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };
        }

        if (self.button) |*button| {
            try button.start();

            button.setPosition(.{
                .x = bgRect.transform.relX(0.5) - @divTrunc(button.rect.transform.w, 2),
                .y = bgRect.transform.relY(0.9) - @divTrunc(button.rect.transform.h, 2),
            });

            button.rect.rounded = true;
        }

        self.isoTitle = Text.init("No ISO selected...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    }

    debug.print("\nISOFilePickerUI: component start() finished.");
}

pub fn handleEvent(self: *ISOFilePickerUI, event: ComponentEvent) !EventResult {
    debug.printf("\nISOFilePickerUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {
        //
        Events.onISOFilePathChanged.Hash => {
            //
            const data = Events.onISOFilePathChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

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

                // TODO: must be released in deinit()
                newName = data.newPath[lastSlash + 1 .. data.newPath.len :0];
            }

            if (self.bgRect) |bgRect| {
                self.isoTitle = Text.init(newName, .{
                    .x = bgRect.transform.relX(0.5),
                    .y = bgRect.transform.relY(0.5),
                }, .{
                    .fontSize = 14,
                });
            }
        },

        // NOTE: Deprecated implementation. Use Events.onUIDimensionsQueried.
        // ISOFilePickerUI emits this event in response to receiving the same event
        Events.onGetUIDimensions.Hash => {
            //
            const data = Events.onGetUIDimensions.Data{ .transform = self.bgRect.?.transform };

            eventResult.validate(1);

            const responseEvent = Events.onGetUIDimensions.create(self.asComponentPtr(), &data);

            EventManager.broadcast(responseEvent);
        },

        Events.onUIDimensionsQueried.Hash => {
            eventResult.validate(1);

            const responseDataPtr: *Events.onUIDimensionsQueried.Response = try self.allocator.create(Events.onUIDimensionsQueried.Response);
            responseDataPtr.* = .{ .bgRectWidth = if (self.bgRect) |bgRect| bgRect.transform.w else 0 };
            eventResult.data = @ptrCast(@alignCast(responseDataPtr));
        },

        ISOFilePicker.Events.onActiveStateChanged.Hash => {
            //
            const data = ISOFilePicker.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            switch (data.isActive) {
                true => {
                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.white;
                    }

                    if (self.diskImg) |*img| {
                        img.transform.scale = 1.0;
                    }
                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.violet,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.offWhite;
                    }

                    if (self.diskImg) |*img| {
                        img.transform.scale = 0.7;
                    }

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                        .color = Color.darkViolet,
                        .borderColor = Color.transparentDark,
                    });
                },
            }

            const responseEvent = Events.onGetUIDimensions.create(
                &self.component.?,
                &.{ .transform = self.bgRect.?.transform },
            );

            EventManager.broadcast(responseEvent);
        },

        else => {},
    }

    return eventResult;
}

fn recalculateUI(self: *ISOFilePickerUI, bgRectParams: BgRectParams) void {
    debug.print("\nIsoFilePickerUI: recalculating UI...");

    if (self.bgRect) |*bgRect| {
        bgRect.transform.w = bgRectParams.width;
        bgRect.style.color = bgRectParams.color;
        bgRect.style.borderStyle.color = bgRectParams.borderColor;

        if (self.headerLabel) |*headerLabel| {
            headerLabel.transform.x = bgRect.transform.x + 12;
            headerLabel.transform.y = bgRect.transform.relY(0.01);
        }

        if (self.diskImg) |*img| {
            img.transform.x = bgRect.transform.relX(0.5) - img.transform.getWidth() / 2;
            img.transform.y = bgRect.transform.relY(0.5) - img.transform.getHeight() / 2;

            if (self.isoTitle) |*isoTitle| {
                isoTitle.transform.x = bgRect.transform.relX(0.5) - isoTitle.getDimensions().width / 2;
                isoTitle.transform.y = img.transform.y + img.transform.getHeight() + winRelY(0.02);
            }
        }

        if (self.button) |*btn| {
            btn.setPosition(.{ .x = bgRect.transform.relX(0.5) - btn.rect.transform.getWidth() / 2, .y = btn.rect.transform.y });
        }
    }
}

pub fn update(self: *ISOFilePickerUI) !void {
    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *ISOFilePickerUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    if (self.bgRect) |bgRect| {
        bgRect.draw();
    }

    if (self.headerLabel) |label| {
        label.draw();
    }

    if (self.diskImg) |img| {
        img.draw();
    }

    if (isActive) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *ISOFilePickerUI) !void {
    if (self.button) |*button| {
        try button.draw();
    }
}

fn drawInactive(self: *ISOFilePickerUI) !void {
    if (self.isoTitle) |isoTitle| {
        isoTitle.draw();
    }
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
