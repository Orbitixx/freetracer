// Renders the image selection panel UI, wiring component events to button, label, and layout updates.
// Receives image path and active state notifications, relays layout geometry to listeners, and never performs disk I/O.
// Owns allocator-backed copies of transient strings so UI state remains valid beyond the originating event scope.
// ----------------------------------------------------------------------------------------------------
const std = @import("std");
const osd = @import("osdialog");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

const AppConfig = @import("../../config.zig");
const freetracer_lib = @import("freetracer-lib");
const Character = freetracer_lib.constants.Character;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const AppManager = @import("../../managers/AppManager.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
pub const ComponentName = EventManager.ComponentName.ISO_FILE_PICKER_UI;

const FilePicker = @import("./FilePicker.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const DeprecatedUI = @import("../ui/import/index.zig");
const Rectangle = DeprecatedUI.Primitives.Rectangle;
const Transform = DeprecatedUI.Primitives.Transform;

const UIFramework = @import("../ui/framework/import.zig");
const View = UIFramework.View;
const Textbox = UIFramework.Textbox;
const FileDropzone = UIFramework.FileDropzone;
const UIChain = UIFramework.UIChain;

const Styles = DeprecatedUI.Styles;
const Color = Styles.Color;

const DEFAULT_ISO_TITLE = "No ISO selected...";
const DEFAULT_SECTION_HEADER = "Select Image";
const DISPLAY_NAME_SUFFIX_LEN: usize = 14;

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
pub const FilePickerUIState = struct {
    isActive: bool = true,
    isoPath: ?[:0]u8 = null,
};
pub const ComponentState = ComponentFramework.ComponentState(FilePickerUIState);

const FilePickerUI = @This();

// Component-agnostic props
state: ComponentState,
parent: *FilePicker,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
displayNameBuffer: [AppConfig.IMAGE_DISPLAY_NAME_BUFFER_LEN:0]u8 = undefined,
layout: View = undefined,

pub const Events = struct {
    pub const onISOFilePathChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "iso_file_path_changed"),
        struct { newPath: [:0]u8, size: ?u64 = null },
        struct {},
    );

    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    // TODO: Check: Deprecated ?
    pub const onGetUIDimensions = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "get_ui_width"),
        struct { transform: Transform },
        struct {},
    );

    // TODO: Deprecated
    pub const onUIDimensionsQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "get_ui"),
        struct { result: **Transform },
        struct {},
    );

    pub const onRootViewTransformQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_root_view_transform_queried"),
        struct { result: **UIFramework.Transform },
        struct {},
    );
};

pub fn init(allocator: std.mem.Allocator, parent: *FilePicker) !FilePickerUI {
    Debug.log(.DEBUG, "FilePickerUI: start() called.", .{});

    return FilePickerUI{
        .allocator = allocator,
        .state = ComponentState.init(FilePickerUIState{}),
        .parent = parent,
    };
}

pub fn initComponent(self: *FilePickerUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

pub fn start(self: *FilePickerUI) !void {
    Debug.log(.DEBUG, "FilePickerUI: component start() called.", .{});

    const component = try self.ensureComponentInitialized();
    try subscribeToEvents(component);
    try self.initLayout();

    Debug.log(.DEBUG, "FilePickerUI: component start() finished.", .{});
}

pub fn handleEvent(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "FilePickerUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        Events.onISOFilePathChanged.Hash => try self.handleIsoFilePathChanged(event),
        // TODO: Deprecated
        // Events.onUIDimensionsQueried.Hash => try self.handleUIDimensionsQueried(event),
        Events.onRootViewTransformQueried.Hash => try self.handleOnRootViewTransformQueried(event),
        FilePicker.Events.onActiveStateChanged.Hash => try self.handleActiveStateChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => eventResult.fail(),
    };
}

pub fn update(self: *FilePickerUI) !void {
    // if (!self.readIsActive()) return;

    try self.layout.update();
}

pub fn draw(self: *FilePickerUI) !void {
    const isActive = self.readIsActive();

    // self.bgRect.draw();
    try self.layout.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

pub fn deinit(self: *FilePickerUI) void {
    self.layout.deinit();
}

pub fn dispatchComponentAction(self: *FilePickerUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(FilePickerUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

fn drawActive(self: *FilePickerUI) !void {
    _ = self;
}

fn drawInactive(self: *FilePickerUI) !void {
    _ = self;
}

fn ensureComponentInitialized(self: *FilePickerUI) !*Component {
    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());
    if (self.component) |*component| return component;
    return error.UnableToSubscribeToEventManager;
}

fn subscribeToEvents(component: *Component) !void {
    if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
}

/// Updates internal active state and reapplies panel styling; must be called on the main UI thread.
fn setIsActive(self: *FilePickerUI, isActive: bool) void {
    self.storeIsActive(isActive);
}

fn storeIsActive(self: *FilePickerUI, isActive: bool) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isActive = isActive;
}

fn readIsActive(self: *FilePickerUI) bool {
    self.state.lock();
    defer self.state.unlock();
    return self.state.data.isActive;
}

fn updateIsoPathState(self: *FilePickerUI, newPath: [:0]u8) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isoPath = newPath;
}

fn extractDisplayName(path: [:0]u8) [:0]const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |index| {
        return path[index + 1 .. path.len :0];
    }
    return path;
}

fn prepareDisplayName(self: *FilePickerUI, newName: [:0]const u8) [:0]const u8 {
    @memset(&self.displayNameBuffer, Character.NULL);

    const capacity = self.displayNameBuffer.len - 1;

    if (newName.len > DISPLAY_NAME_SUFFIX_LEN and capacity > 0) {
        const prefix = "...";
        if (capacity <= prefix.len) {
            const copyLen = @min(newName.len, capacity);
            const startC = newName.len - copyLen;
            @memcpy(self.displayNameBuffer[0..copyLen], newName[startC .. startC + copyLen]);
            self.displayNameBuffer[copyLen] = Character.NULL;
            return self.displayNameBuffer[0..copyLen :0];
        }

        const suffix_len = @min(DISPLAY_NAME_SUFFIX_LEN, capacity - prefix.len);
        const suffix_start = if (suffix_len >= newName.len) 0 else newName.len - suffix_len;

        @memcpy(self.displayNameBuffer[0..prefix.len], prefix);
        @memcpy(
            self.displayNameBuffer[prefix.len .. prefix.len + suffix_len],
            newName[suffix_start .. suffix_start + suffix_len],
        );

        const written = prefix.len + suffix_len;
        self.displayNameBuffer[written] = Character.NULL;
        return self.displayNameBuffer[0..written :0];
    }

    const copyLen = @min(newName.len, capacity);
    @memcpy(self.displayNameBuffer[0..copyLen], newName[0..copyLen]);
    self.displayNameBuffer[copyLen] = Character.NULL;
    return self.displayNameBuffer[0..copyLen :0];
}

fn handleOnRootViewTransformQueried(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onRootViewTransformQueried.getData(event) orelse return eventResult.fail();
    data.result.* = &self.layout.transform;
    return eventResult.succeed();
}

fn handleUIDimensionsQueried(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onUIDimensionsQueried.getData(event) orelse return eventResult.fail();
    data.result.* = &self.bgRect.transform;
    return eventResult.succeed();
}

fn handleActiveStateChanged(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = FilePicker.Events.onActiveStateChanged.getData(event) orelse return eventResult.fail();
    self.setIsActive(data.isActive);

    self.layout.emitEvent(.{ .StateChanged = .{ .isActive = data.isActive } }, .{});

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerHeaderDivider, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerImageSelectedGlowTexture, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerImageSelectedTexture, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerImageSelectedTextbox, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerImageSelectedBarRect, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .FilePickerImageSelectedBarText, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );

    if (!data.isActive) rl.setMouseCursor(.default);
    return eventResult.succeed();
}

fn handleIsoFilePathChanged(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onISOFilePathChanged.getData(event) orelse return eventResult.fail();

    if (data.newPath.len > 0) {
        self.updateIsoPathState(data.newPath);
        const displayName = extractDisplayName(data.newPath);

        var sizeBuf: [36]u8 = std.mem.zeroes([36]u8);

        if (data.size) |size| {
            const displaySize = if (size > 1_000_000_000) @divTrunc(size, 1_000_000_000) else @divTrunc(size, 1_000_000);
            const displayUnits = if (size > 1_000_000_000) "GB" else "MB";

            _ = try std.fmt.bufPrint(sizeBuf[0..], "{d:.0} {s}", .{ displaySize, displayUnits });

            self.layout.emitEvent(.{ .TextChanged = .{
                .target = .FilePickerImageSizeText,
                .text = @ptrCast(std.mem.sliceTo(&sizeBuf, 0x00)),
                .style = .{ .textColor = Color.offWhite },
            } }, .{ .excludeSelf = true });
        }

        self.layout.emitEvent(
            .{ .TextChanged = .{
                .target = .FilePickerImageInfoTextbox,
                .text = displayName,
                .style = UIConfig.Styles.ImageInfoTextbox.Selected.text,
            } },
            .{ .excludeSelf = true },
        );
        self.layout.emitEvent(
            .{ .TextChanged = .{
                .target = .FilePickerImageSelectedTextbox,
                .text = displayName,
            } },
            .{ .excludeSelf = true },
        );
        self.layout.emitEvent(
            .{ .SpriteButtonEnabledChanged = .{ .target = .FilePickerConfirmButton, .enabled = true } },
            .{ .excludeSelf = true },
        );

        // self.updateIsoTitle(displayName);
    } else {
        // self.resetIsoTitle();
    }

    return eventResult.succeed();
}

pub fn handleAppResetRequest(self: *FilePickerUI) EventResult {
    var eventResult = EventResult.init();

    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = true;
        self.state.data.isoPath = null;
    }

    self.setIsActive(true);

    return eventResult.succeed();
}

fn initLayout(self: *FilePickerUI) !void {
    var ui = UIChain.init(self.allocator);

    self.layout = try ui.view(.{
        .id = null,
        .position = .percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, AppConfig.APP_UI_MODULE_PANEL_Y),
        .size = .percent(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE, AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        .relativeTransform = try AppManager.getGlobalTransform(),
        .background = .{
            .transform = .{},
            .style = .{
                .color = Color.themeSectionBg,
                .borderStyle = .{ .color = Color.themeSectionBorder },
            },
            .rounded = true,
            .bordered = true,
        },
    }).children(.{

        //
        ui.texture(.STEP_1_INACTIVE, .{})
            .id("header_icon")
            .position(.percent(0.05, 0.03))
            .positionRef(.Parent)
            .scale(1)
            .callbacks(.{ .onStateChange = .{} }), // Consumes .StateChanged event without doing anything
        //
        ui.textbox(DEFAULT_SECTION_HEADER, UIConfig.Styles.HeaderTextbox, UIFramework.Textbox.Params{ .wordWrap = true })
            .id("header_textbox")
            .position(.percent(1, 0))
            .offset(10, -2)
            .positionRef(.{ .NodeId = "header_icon" })
            .size(.percent(0.7, 0.3))
            .sizeRef(.Parent)
            .callbacks(.{ .onStateChange = .{} }), // Consumes .StateChanged event without doing anything

        ui.rectangle(.{ .style = .{
            .color = Color.themeSectionBorder,
        } })
            .elId(.FilePickerHeaderDivider)
            .id("header_divider")
            .position(.percent(0, 1))
            .positionRefX(.Parent)
            .positionRefY(.{ .NodeId = "header_textbox" })
            .size(.mix(.percent(1), .pixels(2)))
            .sizeRef(.Parent)
            .active(false),

        ui.fileDropzone(.{
            .identifier = .FilePickerFileDropzone,
            .icon = .DOC_IMAGE,
            .callbacks = .{
                .onClick = .{
                    .function = FilePicker.dispatchComponentActionWrapper.call,
                    .context = self.parent,
                },
                .onDrop = .{
                    .function = FilePicker.HandleFileDropWrapper.call,
                    .context = self.parent,
                },
            },
            .style = .{
                .dashLength = 6,
                .gapLength = 4,
            },
        }).id("file_picker_dropzone")
            .position(.percent(0, 1))
            .offset(0, 15)
            .positionRef(.{ .NodeId = "header_icon" })
            .size(.percent(0.9, 0.35)),

        ui.rectangle(.{
            .style = .{
                .roundness = 0.09,
                .color = Color.themeDark,
            },
            .rounded = true,
        }).id("image_info_bg")
            .position(.percent(0, 1))
            .offset(0, 15)
            .positionRef(.{ .NodeId = "file_picker_dropzone" })
            .size(.percent(0.9, 0.25))
            .sizeRef(.Parent),

        ui.texture(.IMAGE_TAG, .{})
            .id("image_info_icon")
            .position(.percent(0.05, 0.15))
            .positionRef(.{ .NodeId = "image_info_bg" })
            .sizeRef(.{ .NodeId = "image_info_bg" }),

        ui.textbox("e.g. Ubuntu 24.04 LTS.iso", UIConfig.Styles.ImageInfoTextbox.Normal, Textbox.Params{
            .identifier = .FilePickerImageInfoTextbox,
            .wordWrap = true,
        })
            .id("image_info_textbox")
            .position(.percent(1.7, 0))
            .offset(0, -4)
            .positionRef(.{ .NodeId = "image_info_icon" })
            .size(.percent(0.8, 0.5)) // Base size for the textbox
            .maxWidth(.percent(0.8)) // Maximum width constraint
            .maxHeight(.percent(0.5)) // Maximum height constraint
            .sizeRef(.{ .NodeId = "image_info_bg" }),

        ui.text("5.06 GB", .{
            .identifier = .FilePickerImageSizeText,
            .style = .{
                .textColor = rl.Color.gray,
            },
        })
            .id("image_info_size_text")
            .position(.percent(0, 1))
            // .offset(0, -24)
            .positionRef(.{ .NodeId = "image_info_textbox" })
            .sizeRef(.{ .NodeId = "image_info_bg" }),

        ui.textbox("Pick an image file such as .iso or .img to flash to device.", UIConfig.Styles.FilePickerHintTextbox, Textbox.Params{})
            .id("file_picker_hint_text")
            .position(.percent(0, 1.3))
            .positionRef(.{ .NodeId = "image_info_bg" })
            .size(.percent(0.65, 0.5))
            .sizeRef(.{ .NodeId = "image_info_bg" }),

        ui.spriteButton(.{
            .text = "Confirm",
            .texture = .BUTTON_FRAME,
            .callbacks = .{
                .onClick = .{
                    .function = UIConfig.Callbacks.ConfirmButton.OnClick.call,
                    .context = self,
                },
            },
            .enabled = false,
            .style = UIConfig.Styles.ConfirmButton,
            .identifier = .FilePickerConfirmButton,
        }).position(.percent(1.1, 0))
            .positionRef(.{ .NodeId = "file_picker_hint_text" })
            .size(.percent(0.3, 0.4))
            .sizeRef(.{ .NodeId = "image_info_bg" }),

        ui.texture(.FILE_SELECTED_GLOW, .{ .identifier = .FilePickerImageSelectedGlowTexture })
            .position(.percent(0.5, 0.5))
            .positionRef(.{ .NodeId = "file_picker_image_selected_texture" })
            .offsetToOrigin()
            .sizeRef(.Parent)
            .scale(1)
            .active(false),

        ui.texture(.FILE_SELECTED, .{ .identifier = .FilePickerImageSelectedTexture })
            .id("file_picker_image_selected_texture")
            .position(.percent(0.5, 0.55))
            .offsetToOrigin()
            .scale(1.8)
            .active(false),

        ui.rectangle(.{
            .style = .{
                .color = Color.themePrimary,
                .roundness = 0.4,
            },
            .rounded = true,
        })
            .id("image_selected_bar")
            .elId(.FilePickerImageSelectedBarRect)
            .position(.percent(0.05, 0.85))
            .positionRef(.Parent)
            .size(.percent(0.9, 0.1))
            .sizeRef(.Parent)
            .active(false),

        ui.text("FILE SELECTED", .{ .style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 20,
            .textColor = Color.themeDark,
        } })
            .elId(.FilePickerImageSelectedBarText)
            .position(.percent(0.5, 0.5))
            .positionRef(.{ .NodeId = "image_selected_bar" })
            .offsetToOrigin()
            .sizeRef(.Parent)
            .active(false),

        ui.text("No image selected", .{ .style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 18,
            .textColor = Color.white,
        } })
            .id("file_picker_selected_file_textbox")
            .elId(.FilePickerImageSelectedTextbox)
            .position(.percent(0.5, -0.8))
            .positionRef(.{ .NodeId = "image_selected_bar" })
            .maxWidth(.percent(0.9))
            .offsetToOrigin()
            .active(false),
    });

    self.layout.callbacks.onStateChange = .{
        .function = UIConfig.Callbacks.MainView.StateChangeHandler.handler,
        .context = &self.layout,
    };

    try self.layout.start();
}

const UIConfig = struct {
    //
    pub const Callbacks = struct {
        //
        pub const MainView = struct {
            //
            pub const StateChangeHandler = struct {
                //
                pub fn handler(ctx: *anyopaque, flag: bool) void {
                    const self: *View = @ptrCast(@alignCast(ctx));

                    switch (flag) {
                        true => {
                            Debug.log(.DEBUG, "Main FilePickerUI View received a SetActive(true) command.", .{});
                            self.transform.position = .percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, AppConfig.APP_UI_MODULE_PANEL_Y);
                            self.transform.size = .percent(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE, AppConfig.APP_UI_MODULE_PANEL_HEIGHT_ACTIVE);
                        },
                        false => {
                            Debug.log(.DEBUG, "Main FilePickerUI View received a SetActive(false) command.", .{});
                            self.transform.position = .percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, AppConfig.APP_UI_MODULE_PANEL_Y_INACTIVE);
                            self.transform.size = .percent(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE, AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE);
                        },
                    }

                    self.transform.resolve();
                }
            };
        };

        const ConfirmButton = struct {
            pub const OnClick = struct {
                pub fn call(ctx: *anyopaque) void {
                    const self: *FilePickerUI = @ptrCast(@alignCast(ctx));

                    self.parent.*.confirmSelectedImageFile() catch |err| {
                        Debug.log(.ERROR, "FilePickerUI: Unable to confirm selected image file. {any}", .{err});

                        const response = osd.message(
                            "Error: unable to confirm the selected image file. Submit bug report on github.com?",
                            .{ .level = .err, .buttons = .yes_no },
                        );

                        if (!response) return;
                        const argv: []const []const u8 = &.{ "open", "https://github.com/orbitixx/freetracer/issues/new/choose" };
                        var ch = std.process.Child.init(argv, self.allocator);
                        ch.spawn() catch return;
                    };
                }
            };
        };

        pub const ImageDropzone = struct {
            //
            pub const StateChangeHandler = struct {
                //
                pub fn handler(ctx: *anyopaque, flag: bool) void {
                    //
                    const self: *FileDropzone = @ptrCast(@alignCast(ctx));
                    self.transform.resolve();
                    self.active = flag;
                }
            };
        };

        pub const ImageFileSelectedTexture = struct {
            pub const StateChangeHandler = struct {
                pub fn handler(ctx: *anyopaque, flag: bool) void {
                    const self: *UIFramework.Texture = @ptrCast(@alignCast(ctx));
                    self.transform.resolve();
                    self.active = flag;
                }
            };
        };
    };

    pub const Styles = struct {
        //
        const HeaderTextbox: Textbox.TextboxStyle = .{
            .background = .{ .color = Color.transparent, .borderStyle = .{ .color = Color.transparent, .thickness = 0 }, .roundness = 0 },
            .text = .{ .font = .JERSEY10_REGULAR, .fontSize = 34, .textColor = Color.white },
            .lineSpacing = -5,
        };

        const ImageInfoTextbox = struct {
            pub const Normal: Textbox.TextboxStyle = .{
                .background = .{
                    .color = Color.transparent,
                    .borderStyle = .{
                        .color = Color.transparent,
                        .thickness = 0,
                    },
                    .roundness = 0,
                },
                .text = .{ .font = .ROBOTO_REGULAR, .fontSize = 24, .textColor = rl.Color.gray },
                .lineSpacing = -5,
            };

            pub const Selected: Textbox.TextboxStyle = .{
                .background = .{
                    .color = Color.transparent,
                    .borderStyle = .{
                        .color = Color.transparent,
                        .thickness = 0,
                    },
                    .roundness = 0,
                },
                .text = .{ .font = .ROBOTO_REGULAR, .fontSize = 24, .textColor = Color.themeDanger },
                .lineSpacing = -5,
            };
        };

        const FilePickerHintTextbox: Textbox.TextboxStyle = .{ .text = .{
            .fontSize = 16,
            .textColor = rl.Color.init(156, 156, 156, 255),
        } };

        const ConfirmButton: UIFramework.SpriteButton.Style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 24,
            .textColor = Color.themePrimary,
            .tint = Color.themePrimary,
            .hoverTint = Color.themeTertiary,
            .hoverTextColor = Color.themeTertiary,
        };

        const SelectedDeviceTextbox: Textbox.TextboxStyle = .{
            .background = .{
                .color = Color.transparent,
                .borderStyle = .{
                    .color = Color.transparent,
                    .thickness = 0,
                },
                .roundness = 0,
            },
            .text = .{ .font = .ROBOTO_REGULAR, .fontSize = 24, .textColor = Color.offWhite },
            .lineSpacing = -5,
        };
    };
};
