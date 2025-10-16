const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");

const AppConfig = @import("../config.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const fs = freetracer_lib.fs;

const ResourceManager = @import("./ResourceManager.zig").ResourceManagerSingleton;
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

    pub fn advanceState(self: *AppManager) !void {
        self.appState = switch (self.appState) {
            .ImageSelection => .DeviceSelection,
            .DeviceSelection => .SelectionConfirmation,
            .SelectionConfirmation => .DataFlashing,
            .DataFlashing => .Idle,
            .Idle => return error.CannotAdvanceStatePastDataFlashedState,
        };
        rl.setMouseCursor(.default);
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

        //----------------------------------------------------------------------------------
        //--- @MANAGERS --------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        try Debug.init(self.allocator, .{ .standaloneLogFilePath = logsPath });
        defer Debug.deinit();

        try WindowManager.init();
        defer WindowManager.deinit();

        try ResourceManager.init(self.allocator);
        defer ResourceManager.deinit();

        try EventManager.init(self.allocator);
        defer EventManager.deinit();

        // TODO: Remember to undo
        // try UpdateManager.init(self.allocator);
        // defer UpdateManager.deinit();

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
            .relativeRef = null,
        };
        self.globalTransform.resolve();

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

        var resetAppButton = Button.init(
            "Restart",
            null,
            .{ .x = WindowManager.relW(0.7), .y = WindowManager.relH(0.05) },
            .Primary,
            .{ .context = self, .function = AppManagerSingleton.resetStateButtonHandler },
            self.allocator,
        );

        try resetAppButton.start();
        resetAppButton.setPosition(.{ .x = 0, .y = 0 });
        resetAppButton.rect.rounded = true;

        //----------------------------------------------------------------------------------
        //--- @END COMPONENTS --------------------------------------------------------------
        //----------------------------------------------------------------------------------

        // const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };
        const backgroundColor: rl.Color = @import("../components/ui/Styles.zig").Color.themeBg;
        // const backgroundColor: rl.Color = .{ .r = 5, .g = 23, .b = 43, .a = 255 };

        try componentRegistry.startAll();

        const logoText = UI.Text.init(
            "freetracer",
            .{ .x = relX(0.08), .y = relY(0.035) },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 40, .textColor = Color.white },
        );

        const subLogoText = UI.Text.init(
            "free and open-source by orbitixx",
            .{ .x = relX(0.08), .y = relY(0.035) + 32 },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 18, .textColor = Color.secondary },
        );

        const versionText = UI.Text.init(
            AppConfig.APP_VERSION,
            .{ .x = relX(0.92), .y = relY(0.05) },
            .{ .font = .JERSEY10_REGULAR, .fontSize = 16, .textColor = Color.secondary },
        );

        // var logText = UI.Text.init(
        //     "",
        //     .{ .x = relX(0.02), .y = relY(0.935) },
        //     .{ .font = .ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray },
        // );
        //
        // const logLineBgRect = UI.Rectangle{
        //     .transform = .{
        //         .x = 0,
        //         .y = relY(0.95),
        //         .w = WindowManager.getWindowWidth(),
        //         .h = relY(0.05),
        //     },
        //     .style = .{
        //         .color = Color.transparentDark,
        //     },
        // };

        // Main application GUI.loop
        while (!rl.windowShouldClose()) { // Detect window close button or ESC key
            //----------------------------------------------------------------------------------
            //--- @UPDATE COMPONENTS -----------------------------------------------------------
            //----------------------------------------------------------------------------------

            // TODO: Remember to re-enable and update Releases URI
            // UpdateManager.update();
            try componentRegistry.updateAll();

            //----------------------------------------------------------------------------------
            //--- @ENDUPDATE COMPONENTS --------------------------------------------------------
            //----------------------------------------------------------------------------------

            //----------------------------------------------------------------------------------
            //--- @DRAW ------------------------------------------------------------------------
            //----------------------------------------------------------------------------------

            rl.beginDrawing();

            rl.clearBackground(backgroundColor);

            UI.BackgroundStars.draw();

            logoText.draw();
            subLogoText.draw();

            versionText.draw();

            try resetAppButton.update();
            try resetAppButton.draw();

            // TODO: unnecessary call on every frame -- extract the whole component out, save as flag
            if (self.appState == .DataFlashing) resetAppButton.setEnabled(false) else resetAppButton.setEnabled(true);

            // logLineBgRect.draw();
            //
            // logText.value = Debug.getLatestLog();
            // logText.draw();

            // UpdateManager.draw();
            try componentRegistry.drawAll();

            rl.endDrawing();

            //----------------------------------------------------------------------------------
            //--- @END DRAW --------------------------------------------------------------------
            //----------------------------------------------------------------------------------

        }
    }
};

pub fn resetStateButtonHandler(ctx: *anyopaque) void {
    var self: *AppManager = @ptrCast(@alignCast(ctx));
    self.resetState();
}
