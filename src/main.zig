const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const osd = @import("osdialog");
const env = @import("env.zig");

const Logger = @import("managers/GlobalLogger.zig").LoggerSingleton;
const ResourceManager = @import("managers/ResourceManager.zig").ResourceManagerSingleton;
const WindowManager = @import("managers/WindowManager.zig").WindowManagerSingleton;

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");
const PrivilegedHelper = @import("modules/macos/PrivilegedHelper.zig");

const AppObserver = @import("observers/AppObserver.zig").AppObserver;

const Component = @import("components/Component.zig");
const ComponentID = @import("components/Registry.zig").ComponentID;
const ComponentRegistry = @import("components/Registry.zig").ComponentRegistry;

const Font = @import("managers/ResourceManager.zig").FONT;

const FilePickerComponent = @import("components/FilePicker/Component.zig");
const USBDevicesListComponent = @import("components/USBDevicesList/Component.zig");

const ComponentFramework = @import("./components/framework/import/index.zig");
const TestFilePickerComponent = @import("./components/TestComponent/TestComponent.zig").ISOFilePickerComponent;
const newComponentID = ComponentFramework.ComponentID;

const relH = WindowManager.relH;
const relW = WindowManager.relW;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    //----------------------------------------------------------------------------------
    //--- @MANAGERS --------------------------------------------------------------------
    //----------------------------------------------------------------------------------

    try Logger.init(allocator);
    defer Logger.deinit();

    try WindowManager.init();
    defer WindowManager.deinit();

    try ResourceManager.init(allocator);
    defer ResourceManager.deinit();

    //----------------------------------------------------------------------------------
    //--- @END MANAGERS ----------------------------------------------------------------
    //----------------------------------------------------------------------------------

    //----------------------------------------------------------------------------------
    //--- @COMPONENTS ------------------------------------------------------------------
    //----------------------------------------------------------------------------------

    var componentRegistry: ComponentRegistry = .{ .components = std.AutoHashMap(ComponentID, Component).init(allocator) };
    defer componentRegistry.deinit();

    const appObserver: AppObserver = .{ .componentRegistry = &componentRegistry };

    componentRegistry.registerComponent(
        ComponentID.ISOFilePicker,
        FilePickerComponent.init(allocator, &appObserver).asComponent(),
    );

    componentRegistry.registerComponent(
        ComponentID.USBDevicesList,
        USBDevicesListComponent.init(allocator, &appObserver).asComponent(),
    );

    //----------------------------------------------------------------------------------
    // --- New Component framework ---
    //----------------------------------------------------------------------------------

    var newRegistry = ComponentFramework.ComponentRegistry.init(allocator);
    defer newRegistry.deinit();

    var testFilePickerComponent = TestFilePickerComponent.init(allocator, &appObserver);

    try newRegistry.register(newComponentID.ISOFilePicker, testFilePickerComponent.asComponent());

    //----------------------------------------------------------------------------------
    //--- @END COMPONENTS --------------------------------------------------------------
    //----------------------------------------------------------------------------------

    var helperResponse: bool = false;
    helperResponse = true;
    // if (!PrivilegedHelper.isHelperToolInstalled()) {
    // helperResponse = PrivilegedHelper.installPrivilegedHelperTool();
    // } else helperResponse = true;

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    try newRegistry.initAll();

    const tcomp: *TestFilePickerComponent = @ptrCast(@alignCast(newRegistry.components.get(newComponentID.ISOFilePicker).?.ptr));
    try tcomp.worker.?.start();

    debug.print("\nMade it past threading...");

    // Main application GUI.loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        //--- @UPDATE COMPONENTS -----------------------------------------------------------
        //----------------------------------------------------------------------------------

        componentRegistry.processUpdates();

        try newRegistry.updateAll();

        //----------------------------------------------------------------------------------
        //--- @ENDUPDATE COMPONENTS --------------------------------------------------------
        //----------------------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @DRAW ------------------------------------------------------------------------
        //----------------------------------------------------------------------------------

        rl.beginDrawing();

        rl.clearBackground(backgroundColor);

        rl.drawTextEx(
            ResourceManager.getFont(Font.JERSEY10_REGULAR),
            "freetracer",
            .{ .x = relW(0.08), .y = relH(0.035) },
            40,
            0,
            .white,
        );

        rl.drawTextEx(
            ResourceManager.getFont(Font.JERSEY10_REGULAR),
            "free and open-source by orbitixx",
            .{ .x = relW(0.08), .y = relH(0.035) + 32 },
            18,
            0,
            rl.Color.init(78, 96, 121, 255),
        );

        rl.drawCircleV(.{ .x = relW(0.9), .y = relH(0.065) }, 4.5, if (helperResponse) .green else .red);
        rl.drawCircleLinesV(.{ .x = relW(0.9), .y = relH(0.065) }, 4.5, .white);

        rl.drawTextEx(
            ResourceManager.getFont(Font.JERSEY10_REGULAR),
            env.APP_VERSION,
            .{ .x = relW(0.92), .y = relH(0.05) },
            16,
            0,
            rl.Color.init(78, 96, 121, 255),
        );

        rl.drawRectangleRec(rl.Rectangle.init(0, relH(0.94), WindowManager.getWindowWidth(), relH(0.06)), rl.Color.init(0, 0, 0, 60));

        rl.drawTextEx(
            ResourceManager.getFont(Font.ROBOTO_REGULAR),
            Logger.getLatestLog(),
            .{ .x = relW(0.02), .y = relH(0.93) },
            14,
            0,
            .light_gray,
        );

        componentRegistry.processRendering();

        try newRegistry.drawAll();

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
    //     debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
    //     break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    // };
    //
    // defer usbStorageDevices.deinit();
    //
    // if (usbStorageDevices.items.len > 0) {
    //     if (std.mem.count(u8, usbStorageDevices.items[0].bsdName, "disk4") > 0) {
    //         debug.print("\nFound disk4 by literal. Preparing to unmount...");
    //         DiskArbitration.unmountAllVolumes(&usbStorageDevices.items[0]) catch |err| {
    //             debug.printf("\nERROR: Failed to unmount volumes on {s}. Error message: {any}", .{ usbStorageDevices.items[0].bsdName, err });
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
