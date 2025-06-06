const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const ISOFilePicker = @import("./FilePicker.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;
const Styles = UIFramework.Styles;

pub const ISOFilePickerUIState = struct {
    active: bool = true,
    isoPath: ?[:0]u8 = null,
};
pub const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);

const ISOFilePickerUI = @This();

// Component-agnostic props
state: ComponentState,
parent: *ISOFilePicker,
component: ?Component = null,

// Component-specific, unique props
bgRect: ?Rectangle = null,
headerText: ?Text = null,
diskImg: ?Texture = null,
button: ?Button = null,
isoTitle: ?Text = null,

pub const Events = struct {
    pub const ISOFilePathChanged = ComponentFramework.defineEvent(
        "iso_file_picker_ui.iso_file_path_changed",
        struct { newPath: [:0]u8 },
    );

    pub const ISOFilePickerActiveStateChanged = ComponentFramework.defineEvent(
        "iso_file_picker_ui.active_state_changed",
        struct { isActive: bool },
    );
};

pub fn init(parent: *ISOFilePicker) !ISOFilePickerUI {
    debug.print("\nISOFilePickerUI: start() called.");

    return ISOFilePickerUI{
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

    self.bgRect = Rectangle{
        .transform = .{ .x = winRelX(0.08), .y = winRelY(0.2), .w = winRelX(0.35), .h = winRelY(0.7) },
        .style = .{
            .color = Styles.Color.violet,
            .borderStyle = .{
                .color = Styles.Color.white,
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

        self.headerText = Text.init("image", .{
            .x = bgRect.transform.x + 12,
            .y = bgRect.transform.relY(0.01),
        }, .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Styles.Color.white,
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
    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    block: switch (event.hash) {
        Events.ISOFilePathChanged.Hash => {
            // TODO: handle null data gracefully
            const data = Events.ISOFilePathChanged.getData(&event).?;
            if (@TypeOf(data.*) != Events.ISOFilePathChanged.Data) break :block;

            eventResult.success = true;
            eventResult.validation = 1;

            var state = self.state.getData();

            state.isoPath = data.newPath;

            var newName: [:0]const u8 = @ptrCast("No ISO selected...");

            if (state.isoPath) |path| {

                // const path: [:0]const u8 = data.newPath orelse "No ISO selected...";
                var lastSlash: usize = 0;

                for (0..path.len) |i| {
                    // Find the last forward slash in the path (0x2f)
                    if (path[i] == 0x2f) lastSlash = i;
                }

                // TODO: must be released in deinit()
                newName = path[lastSlash + 1 .. path.len :0];
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

        Events.ISOFilePickerActiveStateChanged.Hash => {
            const data = Events.ISOFilePickerActiveStateChanged.getData(&event).?;
            if (@TypeOf(data.*) != Events.ISOFilePickerActiveStateChanged.Data) break :block;

            eventResult.success = true;
            eventResult.validation = 1;

            var state = self.state.getData();
            state.active = data.isActive;

            switch (state.active) {
                true => {
                    if (self.bgRect) |*bgRect| {
                        bgRect.transform.w = winRelX(0.35);
                        bgRect.style.color = Styles.Color.violet;
                        bgRect.style.borderStyle.color = Styles.Color.white;

                        if (self.isoTitle) |*isoTitle| {
                            isoTitle.transform.x = bgRect.transform.relX(0.5) - isoTitle.getDimensions().width / 2;
                            isoTitle.transform.y = bgRect.transform.relY(0.5) - isoTitle.getDimensions().height / 2;
                        }
                    }
                },
                false => {
                    if (self.bgRect) |*bgRect| {
                        bgRect.transform.w = winRelX(0.16);
                        bgRect.style.color = Styles.Color.transparentDark;
                        bgRect.style.borderStyle.color = Styles.Color.transparentDark;

                        if (self.isoTitle) |*isoTitle| {
                            isoTitle.transform.x = bgRect.transform.relX(0.5) - isoTitle.getDimensions().width / 2;
                            isoTitle.transform.y = bgRect.transform.relY(0.5) - isoTitle.getDimensions().height / 2;
                        }
                    }
                },
            }
        },
        else => {},
    }

    return eventResult;
}

pub fn update(self: *ISOFilePickerUI) !void {
    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *ISOFilePickerUI) !void {
    const state = self.state.getDataLocked();
    defer self.state.unlock();

    if (self.bgRect) |bgRect| {
        bgRect.draw();
    }

    if (self.headerText) |text| {
        text.draw();
    }

    if (state.active) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *ISOFilePickerUI) !void {
    if (self.diskImg) |img| {
        img.draw();
    }

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
