// Renders the image selection panel UI, wiring component events to button, label, and layout updates.
// Receives image path and active state notifications, relays layout geometry to listeners, and never performs disk I/O.
// Owns allocator-backed copies of transient strings so UI state remains valid beyond the originating event scope.
// ----------------------------------------------------------------------------------------------------
const std = @import("std");
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
const Button = UIFramework.Button;
const Rectangle = UIFramework.Primitives.Rectangle;
const Transform = UIFramework.Primitives.Transform;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;
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
diskImg: Texture = undefined,
button: Button = undefined,
isoTitle: Text = undefined,
displayNameBuffer: [AppConfig.IMAGE_DISPLAY_NAME_BUFFER_LEN:0]u8 = undefined,
header: SectionHeader = undefined,
// headerFrame: UIFramework.Layout.Bounds = undefined,

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
    try self.button.update();
}

pub fn draw(self: *FilePickerUI) !void {
    self.state.lock();
    defer self.state.unlock();
    const isActive = self.state.data.isActive;

    self.bgRect.draw();
    // self.headerLabel.draw();
    self.diskImg.draw();
    try self.header.textbox.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
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

fn drawActive(self: *FilePickerUI) !void {
    try self.button.draw();
}

fn drawInactive(self: *FilePickerUI) !void {
    self.isoTitle.draw();
}

fn recalculateUI(self: *FilePickerUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "FilePickerUI: recalculating UI...", .{});

    self.bgRect.transform.w = bgRectParams.width;
    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    self.diskImg.transform.x = self.bgRect.transform.relX(0.5) - self.diskImg.transform.getWidth() / 2;
    self.diskImg.transform.y = self.bgRect.transform.relY(0.5) - self.diskImg.transform.getHeight() / 2;

    self.setImageTitlePosition();

    self.button.setPosition(.{ .x = self.bgRect.transform.relX(0.5) - self.button.rect.transform.getWidth() / 2, .y = self.button.rect.transform.y });
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
    self.initializeDiskImage();
    self.initializeIsoTitle();
    try self.initializeButton();
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

    self.header = .{
        .textboxFrame = Bounds.relative(
            &self.bgRect.transform,
            PositionSpec.pixels(10, 0),
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

fn initializeDiskImage(self: *FilePickerUI) void {
    self.diskImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.diskImg.transform.x = self.bgRect.transform.relX(0.5) - self.diskImg.transform.w / 2;
    self.diskImg.transform.y = self.bgRect.transform.relY(0.5) - self.diskImg.transform.h / 2;
    self.diskImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };
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

    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.w, 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.h, 2),
    });

    self.button.rect.rounded = true;
}

fn initializeIsoTitle(self: *FilePickerUI) void {
    self.displayNameBuffer = std.mem.zeroes([AppConfig.IMAGE_DISPLAY_NAME_BUFFER_LEN:0]u8);
    self.resetIsoTitle();
}

fn applyAppearance(self: *FilePickerUI, params: BgRectParams, headerColor: rl.Color, diskScale: f32) void {
    self.headerLabel.style.textColor = headerColor;
    self.diskImg.transform.scale = diskScale;
    self.recalculateUI(params);
}

fn broadcastUIDimensions(self: *FilePickerUI) void {
    const responseEvent = Events.onGetUIDimensions.create(self.asComponentPtr(), &.{ .transform = self.bgRect.transform });
    EventManager.broadcast(responseEvent);
}

/// Updates internal active state and reapplies panel styling; must be called on the main UI thread.
fn setIsActive(self: *FilePickerUI, isActive: bool) void {
    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = isActive;
    }

    if (isActive) {
        self.applyAppearance(.{
            .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
            .color = Color.themeSectionBg,
            .borderColor = Color.themeSectionBorder,
        }, Color.white, 1.0);
    } else {
        self.applyAppearance(.{
            .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
            .color = Color.themeSectionBg,
            .borderColor = Color.themeSectionBorder,
        }, Color.offWhite, 0.7);
    }

    self.broadcastUIDimensions();
}

fn updateIsoPathState(self: *FilePickerUI, newPath: [:0]u8) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isoPath = newPath;
}

fn extractDisplayName(path: [:0]u8) [:0]const u8 {
    var lastSlash: usize = 0;
    for (0..path.len) |i| {
        if (path[i] == '/') lastSlash = i;
    }
    return path[lastSlash + 1 .. path.len :0];
}

fn updateIsoTitle(self: *FilePickerUI, newName: [:0]const u8) void {
    @memset(&self.displayNameBuffer, Character.NULL);

    const written = if (newName.len > 14) blk: {
        const prefix = "...";
        @memcpy(self.displayNameBuffer[0..prefix.len], prefix);
        @memcpy(self.displayNameBuffer[prefix.len .. prefix.len + 14], newName[newName.len - 14 ..]);
        break :blk prefix.len + 14;
    } else blk: {
        @memcpy(self.displayNameBuffer[0..newName.len], newName);
        break :blk newName.len;
    };

    self.displayNameBuffer[written] = Character.NULL;

    const label = std.mem.sliceTo(&self.displayNameBuffer, Character.NULL);

    self.isoTitle = Text.init(@ptrCast(label), .{
        .x = self.bgRect.transform.relX(0.5),
        .y = self.bgRect.transform.relY(0.5),
    }, .{ .fontSize = 14 });

    self.setImageTitlePosition();
}

fn resetIsoTitle(self: *FilePickerUI) void {
    self.isoTitle = Text.init(DEFAULT_ISO_TITLE, .{
        .x = self.bgRect.transform.relX(0.5),
        .y = self.bgRect.transform.relY(0.5),
    }, .{ .fontSize = 14 });

    self.setImageTitlePosition();
}

/// Keeps the ISO title centered beneath the disk glyph after any layout or text change.
fn setImageTitlePosition(self: *FilePickerUI) void {
    self.isoTitle.transform.x = self.bgRect.transform.relX(0.5) - self.isoTitle.getDimensions().width / 2;
    self.isoTitle.transform.y = self.diskImg.transform.y + self.diskImg.transform.getHeight() + winRelY(0.02);
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
    _ = self;
    return eventResult.succeed();
}
