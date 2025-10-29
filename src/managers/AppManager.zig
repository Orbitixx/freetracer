const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");

const AppConfig = @import("../config.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const fs = freetracer_lib.fs;

const ResourceManager = @import("./ResourceManager.zig").ResourceManagerSingleton;
const PreferencesManager = @import("./PreferencesManager.zig");
const WindowManager = @import("./WindowManager.zig").WindowManagerSingleton;
const EventManager = @import("./EventManager.zig").EventManagerSingleton;
const UpdateManager = @import("./UpdateManager.zig").UpdateManagerSingleton;

const Font = ResourceManager.FONT;
const Color = @import("../components/ui/Styles.zig").Color;

const ComponentFramework = @import("../components/framework/import/index.zig");
const ComponentID = ComponentFramework.ComponentID;

const ISOFilePicker = @import("../components/FilePicker/FilePicker.zig");
const DeviceList = @import("../components/DeviceList/DeviceList.zig");
const DataFlasher = @import("../components/DataFlasher/DataFlasher.zig");
const PrivilegedHelper = @import("../components/macos/PrivilegedHelper.zig");

const UI = @import("../components/ui/import/index.zig");
const Button = @import("../components/ui/Button.zig");
const Checkbox = @import("../components/ui/Checkbox.zig");
const Rectangle = UI.RectanglePro;

const UIFramework = @import("../components/ui/framework/import.zig");
const Transform = UIFramework.Transform;
const View = UIFramework.View;
const UIChain = UIFramework.UIChain;
const Texture = UIFramework.Texture;

const relY = WindowManager.relH;
const relX = WindowManager.relW;

pub const AppManagerSingleton = @This();

const AppState = enum(u8) {
    ImageSelection,
    DeviceSelection,
    SelectionConfirmation,
    DataFlashing,
    Idle,
};

const ActionRequest = enum(u8) {
    ActivateDeviceList,
    ActivateDataFlasher,
    BeginDataFlashing,
};

const ActionReport = enum(u8) {
    ImageSelected,
    DeviceSelected,
    SelectionConfirmed,
    DataFlashed,
};

pub const Events = struct {
    pub const AppResetEvent = ComponentFramework.defineEvent(
        EventManager.createEventName("AppManager", "on_app_reset_requested"),
        struct {},
        struct {},
    );
};

var instance: ?AppManager = null;

pub fn init(allocator: std.mem.Allocator) !void {
    if (instance != null) {
        Debug.log(.ERROR, "Attempted to init() an App Manager instance despite one already initialized.", .{});
        return error.AppManagerInstanceAlreadyExists;
    }

    instance = .{
        .allocator = allocator,
        .appState = .ImageSelection,
        .lastAction = null,
        .globalTransform = .{},
        .layout = undefined,
    };
}

pub fn startApp() !void {
    if (instance) |*inst| try inst.run() else return error.AppManagerInstanceIsNULL;
}

pub fn authorizeAction(action: ActionRequest) bool {
    Debug.log(.INFO, "AppManager received action aurhotization request: {any}, state: {any}", .{ action, instance.?.appState });
    return if (instance) |*inst| inst.isValidAction(action) else false;
}

pub fn reportAction(action: ActionReport) !void {
    if (instance) |*inst| {
        if (action == .ImageSelected or action == .DeviceSelected or action == .SelectionConfirmed or action == .DataFlashed) {
            Debug.log(.DEBUG, "AppManager: action reported: {any}, current state: {any}", .{ action, inst.appState });
            inst.lastAction = action;
            try inst.advanceState();
            Debug.log(.DEBUG, "AppManager: state successfully transitioned to {any}", .{inst.appState});
        }
    } else return error.AppManagerInstanceIsNULL;
}

pub fn getState() !AppState {
    return if (instance) |inst| return inst.appState else return error.AppManagerInstanceIsNULL;
}

pub fn getGlobalTransform() !*Transform {
    if (instance) |*inst| return &inst.*.globalTransform else return error.AppManagerInstanceIsNULL;
}

const AppManager = struct {
    allocator: std.mem.Allocator,
    appState: AppState,
    lastAction: ?ActionReport,
    globalTransform: Transform,
    layout: View,

    pub fn advanceState(self: *AppManager) !void {
        self.appState = switch (self.appState) {
            .ImageSelection => .DeviceSelection,
            .DeviceSelection => .SelectionConfirmation,
            .SelectionConfirmation => .DataFlashing,
            .DataFlashing => .Idle,
            .Idle => return error.CannotAdvanceStatePastDataFlashedState,
        };
        rl.setMouseCursor(.default);

        if (self.appState == .SelectionConfirmation) self.layout.emitEvent(
            .{ .PositionChanged = .{ .target = .AppManagerSatteliteGraphic, .position = .percent(0.3, 0.3) } },
            .{ .excludeSelf = true },
        );

        if (self.appState != .ImageSelection) {
            self.layout.emitEvent(
                .{ .StateChanged = .{ .target = .AppManagerResetAppButton, .isActive = true } },
                .{ .excludeSelf = true },
            );
        }

        if (self.appState == .DataFlashing) self.layout.emitEvent(.{
            .SpriteButtonEnabledChanged = .{ .target = .AppManagerResetAppButton, .enabled = false },
        }, .{ .excludeSelf = true });

        if (self.appState == .Idle) self.layout.emitEvent(.{
            .SpriteButtonEnabledChanged = .{ .target = .AppManagerResetAppButton, .enabled = true },
        }, .{ .excludeSelf = true });
    }

    pub fn resetState(self: *AppManager) void {
        if (self.appState == .DataFlashing) {
            Debug.log(.WARNING, "AppManager: Cannot reset app state while flashing is in progress...", .{});
            return;
        }

        self.appState = .ImageSelection;
        self.lastAction = null;

        const resetEvent = Events.AppResetEvent.create(null, null);
        EventManager.broadcast(resetEvent);

        self.layout.emitEvent(
            .{ .StateChanged = .{ .target = .AppManagerResetAppButton, .isActive = false } },
            .{ .excludeSelf = true },
        );

        self.layout.emitEvent(
            .{ .PositionChanged = .{ .target = .AppManagerSatteliteGraphic, .position = .percent(0.7, 0.3) } },
            .{ .excludeSelf = true },
        );

        Debug.log(.INFO, "AppManager: state reset to {any}.", .{self.appState});
    }

    pub fn isValidAction(self: *AppManager, action: ActionRequest) bool {
        if (self.lastAction == null) return false;

        return switch (action) {
            .ActivateDeviceList => if (self.lastAction.? == .ImageSelected and self.appState == .DeviceSelection) true else false,
            .ActivateDataFlasher => if (self.lastAction.? == .DeviceSelected and self.appState == .SelectionConfirmation) true else false,
            .BeginDataFlashing => if (self.lastAction.? == .SelectionConfirmed and self.appState == .DataFlashing) true else false,
        };
    }

    pub fn run(self: *AppManager) !void {
        var logsPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
        const logsPath = try fs.unwrapUserHomePath(&logsPathBuffer, AppConfig.MAIN_APP_LOGS_PATH);

        var prefsPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
        const prefsPath = try fs.unwrapUserHomePath(&prefsPathBuffer, AppConfig.PREFERENCES_PATH);

        //----------------------------------------------------------------------------------
        //--- @MANAGERS --------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        try Debug.init(self.allocator, .{ .standaloneLogFilePath = logsPath });
        defer Debug.deinit();

        var isFirstAppLaunch = try PreferencesManager.init(self.allocator, prefsPath);
        defer PreferencesManager.deinit();

        try Debug.setLoggingSeverity(try PreferencesManager.getDebugLevel());

        try WindowManager.init();
        defer WindowManager.deinit();

        try ResourceManager.init(self.allocator);
        defer ResourceManager.deinit();

        try EventManager.init(self.allocator);
        defer EventManager.deinit();

        try UpdateManager.init(
            self.allocator,
            if (isFirstAppLaunch) true else PreferencesManager.getCheckUpdates() catch false,
            !isFirstAppLaunch,
        );
        defer UpdateManager.deinit();

        // Belongs in WindowManager maybe?
        self.globalTransform = Transform{
            .x = 0,
            .y = 0,
            .w = WindowManager.getWindowWidth(),
            .h = WindowManager.getWindowHeight(),
            .size = .pixels(WindowManager.getWindowWidth(), WindowManager.getWindowHeight()),
            .position_ref = null,
            .size_ref = null,
            .relative = null,
            .relativeTransform = null,
        };
        self.globalTransform.resolve();

        var ui = UIChain.init(self.allocator);
        self.layout = try self.initLayout(&ui);
        defer self.layout.deinit();
        try self.layout.start();

        Debug.log(.DEBUG, "Global Transform set: {any}", .{self.globalTransform});

        //----------------------------------------------------------------------------------
        //--- @END MANAGERS ----------------------------------------------------------------
        //----------------------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @COMPONENTS ------------------------------------------------------------------
        //----------------------------------------------------------------------------------

        var componentRegistry = ComponentFramework.Registry.init(self.allocator);
        defer componentRegistry.deinit();

        var isoFilePicker = try ISOFilePicker.init(self.allocator);
        try componentRegistry.register(ComponentID.ISOFilePicker, @constCast(isoFilePicker.asComponentPtr()));
        try isoFilePicker.start();

        var deviceList = try DeviceList.init(self.allocator);
        try componentRegistry.register(ComponentID.DeviceList, @constCast(deviceList.asComponentPtr()));
        try deviceList.start();

        var dataFlasher = try DataFlasher.init(self.allocator);
        try componentRegistry.register(ComponentID.DataFlasher, @constCast(dataFlasher.asComponentPtr()));
        try dataFlasher.start();

        var privilegedHelper = try PrivilegedHelper.init(self.allocator);
        try componentRegistry.register(ComponentID.PrivilegedHelper, @constCast(privilegedHelper.asComponentPtr()));
        try privilegedHelper.start();

        //----------------------------------------------------------------------------------
        //--- @END COMPONENTS --------------------------------------------------------------
        //----------------------------------------------------------------------------------

        // const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };
        const backgroundColor: rl.Color = @import("../components/ui/Styles.zig").Color.themeBg;
        // const backgroundColor: rl.Color = .{ .r = 5, .g = 23, .b = 43, .a = 255 };

        try componentRegistry.startAll();

        const logoText = UI.Text.init(
            "freetracer",
            .{ .x = relX(0.06), .y = relY(0.035) },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 40, .textColor = Color.white },
        );

        const subLogoText = UI.Text.init(
            "free and open-source by orbitixx",
            .{ .x = relX(0.06), .y = relY(0.035) + 32 },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 18, .textColor = Color.secondary },
        );

        const versionText = UI.Text.init(
            AppConfig.APP_VERSION,
            .{ .x = relX(0.92), .y = relY(0.05) },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 16, .textColor = Color.secondary },
        );

        const centerX: i32 = @intFromFloat(WindowManager.getWindowWidth() / 2);
        const centerY: i32 = @intFromFloat(WindowManager.getWindowHeight() / 2);
        const radius: f32 = WindowManager.getWindowWidth() / 2 + WindowManager.getWindowWidth() * 0.2;

        const innerColor: rl.Color = rl.Color.init(32, 32, 44, 255);
        const outerColor: rl.Color = Color.themeBg;

        // Main application GUI.loop
        while (!rl.windowShouldClose()) { // Detect window close button or ESC key
            //----------------------------------------------------------------------------------
            //--- @UPDATE COMPONENTS -----------------------------------------------------------
            //----------------------------------------------------------------------------------

            try self.layout.update();

            UpdateManager.update();
            try componentRegistry.updateAll();

            //----------------------------------------------------------------------------------
            //--- @ENDUPDATE COMPONENTS --------------------------------------------------------
            //----------------------------------------------------------------------------------

            //----------------------------------------------------------------------------------
            //--- @DRAW ------------------------------------------------------------------------
            //----------------------------------------------------------------------------------

            rl.beginDrawing();

            rl.clearBackground(backgroundColor);
            rl.drawCircleGradient(centerX, centerY, radius, innerColor, outerColor);

            UI.BackgroundStars.draw();

            try self.layout.draw();

            logoText.draw();
            subLogoText.draw();
            versionText.draw();

            // TODO: unnecessary call on every frame -- extract the whole component out, save as flag
            // if (self.appState == .DataFlashing) resetAppButton.setEnabled(false) else resetAppButton.setEnabled(true);

            UpdateManager.draw();
            try componentRegistry.drawAll();

            rl.endDrawing();

            if (isFirstAppLaunch) {
                const shouldUpdate = PreferencesManager.getCheckUpdatesPermission();
                if (shouldUpdate) UpdateManager.checkForUpdates();
                isFirstAppLaunch = false;
            }

            //----------------------------------------------------------------------------------
            //--- @END DRAW --------------------------------------------------------------------
            //----------------------------------------------------------------------------------

        }
    }

    fn initLayout(self: *AppManager, ui: *UIChain) !View {
        return try ui.view(.{
            .id = null,
            .position = .percent(0, 0),
            .size = .percent(1, 1),
            .relativeTransform = &self.globalTransform,
            .background = .{
                .transform = .{},
                .style = .{
                    .color = Color.transparent,
                    .borderStyle = .{ .color = Color.transparent },
                },
                .rounded = true,
                .bordered = true,
            },
        }).children(.{
            ui.texture(.ROCKET_GRAPHIC, .{})
                // .elId(.AppManagerRocketGraphic)
                .position(.percent(0.4, 0.38))
                .positionRef(.Parent)
                .scale(2)
                .sizeRef(.Parent)
                .rotation(-33),

            ui.texture(.SATTELITE_GRAPHIC, .{})
                .elId(.AppManagerSatteliteGraphic)
                .position(.percent(0.7, 0.3))
                .positionRef(.Parent)
                .scale(3)
                .sizeRef(.Parent)
                .offsetToOrigin(),

            ui.spriteButton(.{
                .text = "Start Over",
                .texture = .BUTTON_FRAME_DANGER,
                .style = UIConfig.Styles.ResetAppButton,
            })
                .elId(.AppManagerResetAppButton)
                .position(.percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, AppConfig.APP_UI_MODULE_PANEL_Y))
                .positionRef(.Parent)
                .size(.percent(0.13, 0.08))
                .callbacks(.{ .onClick = .{
                    .function = UIConfig.Callbacks.ResetAppButton.OnClick,
                    .context = self,
                } })
                .active(false),
        });
    }
};

pub const UIConfig = struct {
    pub const Callbacks = struct {
        pub const ResetAppButton = struct {
            pub fn OnClick(ctx: *anyopaque) void {
                const appManager: *AppManager = @ptrCast(@alignCast(ctx));
                appManager.resetState();
            }
        };
    };

    pub const Styles = struct {
        const ResetAppButton: UIFramework.SpriteButton.Style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 22,
            .textColor = Color.themeDanger,
            .tint = Color.themeDanger,
            .hoverTint = Color.themeSecondary,
            .hoverTextColor = Color.themeSecondary,
        };
    };
};
