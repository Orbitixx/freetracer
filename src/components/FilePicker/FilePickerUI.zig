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

const UIFramework = @import("../ui/import/index.zig");
const Panel = UIFramework.Panel;
const Button = UIFramework.Button;
const SpriteButton = UIFramework.SpriteButton;
const Rectangle = UIFramework.Primitives.Rectangle;
const Transform = UIFramework.Primitives.Transform;
const Text = UIFramework.Primitives.Text;
const Textbox = UIFramework.Textbox;

const Styles = UIFramework.Styles;
const Color = Styles.Color;
const Layout = UIFramework.Layout;
const Bounds = Layout.Bounds;
const PositionSpec = Layout.PositionSpec;
const UnitValue = Layout.UnitValue;
const Padding = Layout.Padding;
const Spacing = Layout.Space;

const SectionHeader = struct {
    textbox: Textbox,
    textboxFrame: UIFramework.Layout.Bounds,
};

const DEFAULT_ISO_TITLE = "No ISO selected...";
const DISPLAY_NAME_SUFFIX_LEN: usize = 14;

const PanelMode = struct {
    appearance: Panel.Appearance,
    dropzoneStyle: UIFramework.FileDropzone.Style,
};

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
bgRect: Rectangle = undefined,
headerLabel: Text = undefined,
button: Button = undefined,
confirmButton: SpriteButton = undefined,
isoTitle: Text = undefined,
displayNameBuffer: [AppConfig.IMAGE_DISPLAY_NAME_BUFFER_LEN:0]u8 = undefined,
header: SectionHeader = undefined,
stepTexture: UIFramework.Texture = undefined,
dropzoneFrame: Bounds = undefined,
dropzone: UIFramework.FileDropzone = undefined,
// headerFrame: UIFramework.Layout.Bounds = undefined,

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
        struct { result: **Transform },
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
    try self.initializeUIElements();

    self.confirmButton = try SpriteButton.init(
        "Confirm",
        .JERSEY10_REGULAR,
        24,
        Color.themePrimary,
        .BUTTON_FRAME,
        .{ .x = 400, .y = 400, .h = 0, .w = 0 },
        .{ .context = self, .function = FilePickerUI.ConfirmButtonClickHandler.call },
    );
    self.confirmButton.start();

    Debug.log(.DEBUG, "FilePickerUI: component start() finished.", .{});
}

pub fn handleEvent(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "FilePickerUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        Events.onISOFilePathChanged.Hash => try self.handleIsoFilePathChanged(event),
        Events.onUIDimensionsQueried.Hash => try self.handleUIDimensionsQueried(event),
        FilePicker.Events.onActiveStateChanged.Hash => try self.handleActiveStateChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => eventResult.fail(),
    };
}

pub fn update(self: *FilePickerUI) !void {
    if (!self.readIsActive()) return;

    self.dropzone.update();
    try self.button.update();
    try self.confirmButton.update();
}

pub fn draw(self: *FilePickerUI) !void {
    const isActive = self.readIsActive();

    self.bgRect.draw();
    self.stepTexture.draw();
    try self.header.textbox.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();

    self.confirmButton.draw();
}

pub fn deinit(self: *FilePickerUI) void {
    self.button.deinit();
}

pub fn dispatchComponentAction(self: *FilePickerUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(FilePickerUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

fn dropzoneStyleActive() UIFramework.FileDropzone.Style {
    return .{
        .backgroundColor = Styles.Color.themeSectionBg,
        .hoverBackgroundColor = rl.Color.init(35, 39, 55, 255),
        .borderColor = Styles.Color.themeOutline,
        .hoverBorderColor = rl.Color.init(90, 110, 120, 255),
        .dashLength = 10,
        .gapLength = 6,
        .borderThickness = 2,
        .cornerRadius = 0.12,
        .iconScale = 0.3,
    };
}

fn dropzoneStyleInactive() UIFramework.FileDropzone.Style {
    return .{
        .backgroundColor = rl.Color{ .r = 32, .g = 36, .b = 48, .a = 130 },
        .hoverBackgroundColor = rl.Color{ .r = 45, .g = 50, .b = 64, .a = 170 },
        .borderColor = Styles.Color.themeOutline,
        .hoverBorderColor = Styles.Color.lightGray,
        .dashLength = 12,
        .gapLength = 6,
        .borderThickness = 2,
        .cornerRadius = 0.12,
        .iconScale = 0.3,
    };
}

fn panelAppearanceActive() Panel.Appearance {
    return .{
        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
        .backgroundColor = Color.themeSectionBg,
        .borderColor = Color.themeSectionBorder,
        .headerColor = Color.white,
    };
}

fn panelAppearanceInactive() Panel.Appearance {
    return .{
        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
        .backgroundColor = Color.themeSectionBg,
        .borderColor = Color.themeSectionBorder,
        .headerColor = Color.offWhite,
    };
}

fn panelModeActive() PanelMode {
    return .{
        .appearance = panelAppearanceActive(),
        .dropzoneStyle = dropzoneStyleActive(),
    };
}

fn panelModeInactive() PanelMode {
    return .{
        .appearance = panelAppearanceInactive(),
        .dropzoneStyle = dropzoneStyleInactive(),
    };
}

fn panelModeFor(isActive: bool) PanelMode {
    return if (isActive) panelModeActive() else panelModeInactive();
}

fn drawActive(self: *FilePickerUI) !void {
    self.dropzone.draw();
    try self.button.draw();
}

fn drawInactive(self: *FilePickerUI) !void {
    self.isoTitle.draw();
}

fn panelElements(self: *FilePickerUI) Panel.Elements {
    return .{
        .frame = null,
        .rect = &self.bgRect,
        .header = &self.headerLabel,
    };
}

fn applyPanelMode(self: *FilePickerUI, mode: PanelMode) void {
    Debug.log(.DEBUG, "FilePickerUI: applying panel mode.", .{});
    Panel.applyAppearance(self.panelElements(), mode.appearance);
    self.dropzone.setStyle(mode.dropzoneStyle);
    self.dropzoneFrame.parent = &self.bgRect.transform;
    self.dropzone.layoutDirty = true;
    self.refreshLayout();
}

fn refreshLayout(self: *FilePickerUI) void {
    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    self.setImageTitlePosition();
    self.updateButtonPosition();
}

fn updateButtonPosition(self: *FilePickerUI) void {
    const buttonWidth = self.button.rect.transform.getWidth();
    const buttonHeight = self.button.rect.transform.getHeight();
    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - buttonWidth / 2,
        .y = self.bgRect.transform.relY(0.9) - buttonHeight / 2,
    });
}

fn ensureComponentInitialized(self: *FilePickerUI) !*Component {
    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());
    if (self.component) |*component| return component;
    return error.UnableToSubscribeToEventManager;
}

fn subscribeToEvents(component: *Component) !void {
    if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
}

fn initializeUIElements(self: *FilePickerUI) !void {
    self.initializeBackground();
    self.initializeHeader();
    self.initializeDropzone();
    self.initializeIsoTitle();
    try self.initializeButton();
    self.applyPanelMode(panelModeFor(self.readIsActive()));
}

fn initializeBackground(self: *FilePickerUI) void {
    self.bgRect = Rectangle{
        .transform = .{
            .x = winRelX(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X),
            .y = winRelY(AppConfig.APP_UI_MODULE_PANEL_Y),
            .w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
            .h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        },
        .style = .{
            .color = Color.themeSectionBg,
            .borderStyle = .{ .color = Color.themeSectionBorder },
        },
        .rounded = true,
        .bordered = true,
    };
}

fn initializeHeader(self: *FilePickerUI) void {
    self.headerLabel = Text.init("image", .{
        .x = self.bgRect.transform.x + 12,
        .y = self.bgRect.transform.relY(0.01),
    }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Color.white,
    });

    self.stepTexture = UIFramework.Texture.init(.STEP_1_INACTIVE, .{
        .x = self.bgRect.transform.relX(0.05),
        .y = self.bgRect.transform.relY(0.01),
    });

    self.stepTexture.transform.scale = 0.5;

    self.header = .{
        .textboxFrame = Bounds.relative(
            &self.bgRect.transform,
            PositionSpec.percent(0.14, 0),
            .{
                .width = UnitValue.mix(1.0, -48),
                .height = UnitValue.percent(0.25),
            },
        ),

        .textbox = Textbox.init(
            &self.header.textboxFrame,
            "Select image",
            .{
                .background = .{
                    .color = Color.transparent,
                    .borderStyle = .{ .color = Color.transparent, .thickness = 0 },
                    .roundness = 0,
                },
                .text = .{
                    .font = .JERSEY10_REGULAR,
                    .fontSize = 34,
                    .textColor = Color.white,
                },
                .padding = Padding.uniform(Spacing.xs),
                .lineSpacing = -5,
            },
            .{ .wordWrap = true },
            self.allocator,
        ),
    };
}

fn initializeDropzone(self: *FilePickerUI) void {
    const dropzonePosition = PositionSpec.mix(
        UnitValue.percent(0.05),
        UnitValue.percent(0.15),
    );

    const dropzoneSize = Layout.SizeSpec.percent(0.9, 0.3);

    self.dropzoneFrame = Bounds.relative(&self.bgRect.transform, dropzonePosition, dropzoneSize);

    self.dropzone = UIFramework.FileDropzone.init(
        &self.dropzoneFrame,
        .DOC_IMAGE,
        dropzoneStyleActive(),
        .{
            .onClick = .{ .context = self.parent, .function = FilePicker.dispatchComponentActionWrapper.call },
            .onDrop = .{ .context = self.parent, .function = FilePicker.HandleFileDropWrapper.call },
        },
    );

    // self.dropzone.texture.icon
}

fn initializeButton(self: *FilePickerUI) !void {
    self.button = Button.init(
        "SELECT ISO",
        null,
        self.bgRect.transform.getPosition(),
        .Primary,
        .{ .context = self.parent, .function = FilePicker.dispatchComponentActionWrapper.call },
        self.allocator,
    );

    try self.button.start();

    self.updateButtonPosition();

    self.button.rect.rounded = true;
}

fn initializeIsoTitle(self: *FilePickerUI) void {
    self.displayNameBuffer = std.mem.zeroes([AppConfig.IMAGE_DISPLAY_NAME_BUFFER_LEN:0]u8);
    self.isoTitle = Text.init(DEFAULT_ISO_TITLE, .{
        .x = 0,
        .y = 0,
    }, .{ .fontSize = 14 });
    self.setIsoTitleValue(DEFAULT_ISO_TITLE);
}

fn broadcastUIDimensions(self: *FilePickerUI) void {
    const responseEvent = Events.onGetUIDimensions.create(self.asComponentPtr(), &.{ .transform = self.bgRect.transform });
    EventManager.broadcast(responseEvent);
}

/// Updates internal active state and reapplies panel styling; must be called on the main UI thread.
fn setIsActive(self: *FilePickerUI, isActive: bool) void {
    self.storeIsActive(isActive);
    self.applyPanelMode(panelModeFor(isActive));
    self.broadcastUIDimensions();
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

fn updateIsoTitle(self: *FilePickerUI, newName: [:0]const u8) void {
    const label = self.prepareDisplayName(newName);
    self.setIsoTitleValue(label);
}

fn resetIsoTitle(self: *FilePickerUI) void {
    self.displayNameBuffer[0] = Character.NULL;
    self.setIsoTitleValue(DEFAULT_ISO_TITLE);
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

fn setIsoTitleValue(self: *FilePickerUI, value: [:0]const u8) void {
    self.isoTitle.value = value;
    const dims = self.isoTitle.getDimensions();
    self.isoTitle.transform.w = dims.width;
    self.isoTitle.transform.h = dims.height;
    self.setImageTitlePosition();
}

const ConfirmButtonClickHandler = struct {
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

/// Keeps the ISO title centered beneath the disk glyph after any layout or text change.
fn setImageTitlePosition(self: *FilePickerUI) void {
    const dropBounds = self.dropzoneFrame.resolve();
    const dims = self.isoTitle.getDimensions();
    self.isoTitle.transform.x = dropBounds.x + (dropBounds.w / 2) - dims.width / 2;
    self.isoTitle.transform.y = dropBounds.y + dropBounds.h + winRelY(0.02);
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
    if (!data.isActive) rl.setMouseCursor(.default);
    return eventResult.succeed();
}

fn handleIsoFilePathChanged(self: *FilePickerUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onISOFilePathChanged.getData(event) orelse return eventResult.fail();

    if (data.newPath.len > 0) {
        self.updateIsoPathState(data.newPath);
        const displayName = extractDisplayName(data.newPath);
        self.updateIsoTitle(displayName);
    } else {
        self.resetIsoTitle();
    }

    return eventResult.succeed();
}

pub fn handleAppResetRequest(self: *FilePickerUI) EventResult {
    var eventResult = EventResult.init();

    self.resetIsoTitle();

    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = true;
        self.state.data.isoPath = null;
    }

    self.setIsActive(true);

    return eventResult.succeed();
}
