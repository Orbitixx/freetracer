const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const osd = @import("osdialog");
const env = @import("env.zig");

const Logger = @import("managers/GlobalLogger.zig").LoggerSingleton;
const ResourceManager = @import("managers/ResourceManager.zig").ResourceManagerSingleton;
const WindowManager = @import("managers/WindowManager.zig").WindowManagerSingleton;
const EventManager = @import("managers/EventManager.zig").EventManagerSingleton;

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");
const time = @import("lib/util/time.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");

const Font = @import("managers/ResourceManager.zig").FONT;
const Color = @import("components/ui/Styles.zig").Color;

const ComponentFramework = @import("./components/framework/import/index.zig");
const ComponentID = ComponentFramework.ComponentID;

const ISOFilePicker = @import("./components/FilePicker/FilePicker.zig");
const DeviceList = @import("./components/DeviceList/DeviceList.zig");
const DataFlasher = @import("./components/DataFlasher/DataFlasher.zig");
const PrivilegedHelper = @import("./components/macos/PrivilegedHelper.zig");

const UI = @import("./components/ui/Primitives.zig");
const Button = @import("components/ui/Button.zig");
const Checkbox = @import("components/ui/Checkbox.zig");

const relY = WindowManager.relH;
const relX = WindowManager.relW;

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{ .thread_safe = true }).init;
    const allocator = debugAllocator.allocator();

    defer {
        _ = debugAllocator.detectLeaks();
        _ = debugAllocator.deinit();
    }

    //----------------------------------------------------------------------------------
    //--- @MANAGERS --------------------------------------------------------------------
    //----------------------------------------------------------------------------------

    try Logger.init(allocator);
    defer Logger.deinit();

    try debug.init(allocator);
    defer debug.deinit();

    try WindowManager.init();
    defer WindowManager.deinit();

    try ResourceManager.init(allocator);
    defer ResourceManager.deinit();

    try EventManager.init(allocator);
    defer EventManager.deinit();

    //----------------------------------------------------------------------------------
    //--- @END MANAGERS ----------------------------------------------------------------
    //----------------------------------------------------------------------------------

    //----------------------------------------------------------------------------------
    //--- @COMPONENTS ------------------------------------------------------------------
    //----------------------------------------------------------------------------------

    var componentRegistry = ComponentFramework.Registry.init(allocator);
    defer componentRegistry.deinit();

    var isoFilePicker = try ISOFilePicker.init(allocator);
    try componentRegistry.register(ComponentID.ISOFilePicker, @constCast(isoFilePicker.asComponentPtr()));
    try isoFilePicker.start();

    var deviceList = try DeviceList.init(allocator);
    try componentRegistry.register(ComponentID.DeviceList, @constCast(deviceList.asComponentPtr()));
    try deviceList.start();

    var dataFlasher = try DataFlasher.init(allocator);
    try componentRegistry.register(ComponentID.DataFlasher, @constCast(dataFlasher.asComponentPtr()));
    try dataFlasher.start();

    var privilegedHelper = try PrivilegedHelper.init(allocator);
    try componentRegistry.register(ComponentID.PrivilegedHelper, @constCast(privilegedHelper.asComponentPtr()));
    try privilegedHelper.start();

    //----------------------------------------------------------------------------------
    //--- @END COMPONENTS --------------------------------------------------------------
    //----------------------------------------------------------------------------------

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    try componentRegistry.startAll();

    const logoText = UI.Text.init("freetracer", .{ .x = relX(0.08), .y = relY(0.035) }, .{ .font = .JERSEY10_REGULAR, .fontSize = 40, .textColor = Color.white });
    const subLogoText = UI.Text.init("free and open-source by orbitixx", .{ .x = relX(0.08), .y = relY(0.035) + 32 }, .{ .font = .JERSEY10_REGULAR, .fontSize = 18, .textColor = Color.secondary });
    const versionText = UI.Text.init(env.APP_VERSION, .{ .x = relX(0.92), .y = relY(0.05) }, .{ .font = .JERSEY10_REGULAR, .fontSize = 16, .textColor = Color.secondary });
    var logText = UI.Text.init("", .{ .x = relX(0.02), .y = relY(0.93) }, .{ .font = .ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray });

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

        logText.value = Logger.getLatestLog();
        logText.draw();

        try componentRegistry.drawAll();

        defer rl.endDrawing();

        //----------------------------------------------------------------------------------
        //--- @END DRAW --------------------------------------------------------------------
        //----------------------------------------------------------------------------------

    }

    // try IsoParser.parseIso(&allocator, path);
    // try IsoWriter.write(path, "/dev/sdb");

    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/alpine.iso");
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/tinycore.iso");
    //
    //

    // const usbStorageDevices = IOKit.getUSBStorageDevices(&allocator) catch blk: {
    //     debug.print("WARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
    //     break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    // };
    //
    // defer usbStorageDevices.deinit();
    //
    // if (usbStorageDevices.items.len > 0) {
    //     if (std.mem.count(u8, usbStorageDevices.items[0].bsdName, "disk4") > 0) {
    //         debug.print("Found disk4 by literal. Preparing to unmount...");
    //         DiskArbitration.unmountAllVolumes(&usbStorageDevices.items[0]) catch |err| {
    //             debug.printf("ERROR: Failed to unmount volumes on {s}. Error message: {any}", .{ usbStorageDevices.items[0].bsdName, err });
    //         };
    //     }
    // }
    //
    // defer {
    //     for (usbStorageDevices.items) |usbStorageDevice| {
    //         usbStorageDevice.deinit();
    //     }
    // }

    debug.print("\n");
}
