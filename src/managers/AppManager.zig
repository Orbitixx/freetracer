const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");

const env = @import("../env.zig");
const AppConfig = @import("../config.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const ResourceManager = @import("./ResourceManager.zig").ResourceManagerSingleton;
const WindowManager = @import("./WindowManager.zig").WindowManagerSingleton;
const EventManager = @import("./EventManager.zig").EventManagerSingleton;

const Font = ResourceManager.FONT;
const Color = @import("../components/ui/Styles.zig").Color;

const ComponentFramework = @import("../components/framework/import/index.zig");
const ComponentID = ComponentFramework.ComponentID;

const ISOFilePicker = @import("../components/FilePicker/FilePicker.zig");
const DeviceList = @import("../components/DeviceList/DeviceList.zig");
const DataFlasher = @import("../components/DataFlasher/DataFlasher.zig");
const PrivilegedHelper = @import("../components/macos/PrivilegedHelper.zig");

const UI = @import("../components/ui/Primitives.zig");
const Button = @import("../components/ui/Button.zig");
const Checkbox = @import("../components/ui/Checkbox.zig");

const relY = WindowManager.relH;
const relX = WindowManager.relW;

const AppManager = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) AppManager {
    return .{
        .allocator = allocator,
    };
}

pub fn run(self: *AppManager) !void {
    //----------------------------------------------------------------------------------
    //--- @MANAGERS --------------------------------------------------------------------
    //----------------------------------------------------------------------------------
    try Debug.init(self.allocator, .{ .standaloneLogFilePath = env.MAIN_APP_LOGS_PATH });
    defer Debug.deinit();

    try WindowManager.init();
    defer WindowManager.deinit();

    try ResourceManager.init(self.allocator);
    defer ResourceManager.deinit();

    try EventManager.init(self.allocator);
    defer EventManager.deinit();

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

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

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

    var logText = UI.Text.init(
        "",
        .{ .x = relX(0.02), .y = relY(0.93) },
        .{ .font = .ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray },
    );

    const logLineBgRect = UI.Rectangle{
        .transform = .{
            .x = 0,
            .y = relY(0.94),
            .w = WindowManager.getWindowWidth(),
            .h = relY(0.06),
        },
        .style = .{
            .color = Color.transparentDark,
        },
    };

    // Main application GUI.loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        //--- @UPDATE COMPONENTS -----------------------------------------------------------
        //----------------------------------------------------------------------------------

        // _ = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.0, c.TRUE);

        try componentRegistry.updateAll();

        //----------------------------------------------------------------------------------
        //--- @ENDUPDATE COMPONENTS --------------------------------------------------------
        //----------------------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @DRAW ------------------------------------------------------------------------
        //----------------------------------------------------------------------------------

        rl.beginDrawing();

        rl.clearBackground(backgroundColor);

        logoText.draw();
        subLogoText.draw();

        versionText.draw();

        logLineBgRect.draw();

        logText.value = Debug.getLatestLog();
        logText.draw();

        try componentRegistry.drawAll();

        rl.endDrawing();

        //----------------------------------------------------------------------------------
        //--- @END DRAW --------------------------------------------------------------------
        //----------------------------------------------------------------------------------

    }
}
