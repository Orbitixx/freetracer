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
const Color = @import("components/ui/Styles.zig").Color;

// const FilePickerComponent = @import("components/FilePicker/Component.zig");
const USBDevicesListComponent = @import("components/USBDevicesList/Component.zig");

const ComponentFramework = @import("./components/framework/import/index.zig");
const ISOFilePicker = @import("./components/FilePicker/FilePicker.zig");
const DeviceList = @import("./components/DeviceList/DeviceList.zig");

const Button = @import("components/ui/Button.zig");
const Checkbox = @import("components/ui/Checkbox.zig");
const newComponentID = ComponentFramework.ComponentID;

const UI = @import("./components/ui/Primitives.zig");

const relY = WindowManager.relH;
const relX = WindowManager.relW;

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
    //
    const appObserver: AppObserver = .{ .componentRegistry = &componentRegistry };
    //
    // var filePickerComponent = FilePickerComponent.init(allocator, &appObserver);
    //
    // componentRegistry.registerComponent(
    //     ComponentID.ISOFilePicker,
    //     filePickerComponent.asComponent(),
    // );
    //
    // componentRegistry.registerComponent(
    //     ComponentID.USBDevicesList,
    //     USBDevicesListComponent.init(allocator, &appObserver).asComponent(),
    // );

    //----------------------------------------------------------------------------------
    // --- New Component framework ---
    //----------------------------------------------------------------------------------

    var newRegistry = ComponentFramework.Registry.init(allocator);
    defer newRegistry.deinit();

    var isoFilePicker = try ISOFilePicker.init(allocator, &appObserver);
    try newRegistry.register(newComponentID.ISOFilePicker, @constCast(isoFilePicker.asComponentPtr()));

    var deviceList = try DeviceList.init(allocator);
    try newRegistry.register(newComponentID.DeviceList, @constCast(deviceList.asComponentPtr()));

    try deviceList.initWorker();
    deviceList.dispatchComponentAction();

    const dispatchCheckboxActionWrapper = struct {
        pub fn call(ptr: *anyopaque) void {
            _ = ptr;
            debug.print("\nCheckbox action called!");
        }
    };

    var testCheckbox = Checkbox.init(
        "Test checkbox",
        .{ .x = 500, .y = 200 },
        20,
        .Primary,
        .{
            .function = dispatchCheckboxActionWrapper.call,
            .context = &isoFilePicker,
        },
    );
    testCheckbox.outerRect.rounded = true;
    testCheckbox.outerRect.bordered = true;
    testCheckbox.innerRect.bordered = false;
    testCheckbox.innerRect.rounded = true;
    try newRegistry.register(.TestBtn, @constCast(testCheckbox.asComponentPtr()));

    //----------------------------------------------------------------------------------
    //--- @END COMPONENTS --------------------------------------------------------------
    //----------------------------------------------------------------------------------

    var helperResponse: bool = false;
    helperResponse = true;
    // if (!PrivilegedHelper.isHelperToolInstalled()) {
    // helperResponse = PrivilegedHelper.installPrivilegedHelperTool();
    // } else helperResponse = true;

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    try newRegistry.startAll();

    {
        const data: ISOFilePicker.Events.UIWidthChangedEvent.Data = .{ .newWidth = 95 };
        const event = ISOFilePicker.Events.UIWidthChangedEvent.create(@constCast(&isoFilePicker.asComponent()), &data);

        const r = try isoFilePicker.handleEvent(event);
        std.debug.assert(r.success == true and r.validation == 95);
    }

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

        logoText.draw();
        subLogoText.draw();

        rl.drawCircleV(.{ .x = relX(0.9), .y = relY(0.065) }, 4.5, if (helperResponse) .green else .red);
        rl.drawCircleLinesV(.{ .x = relX(0.9), .y = relY(0.065) }, 4.5, .white);

        versionText.draw();

        // rl.drawRectangleRec(rl.Rectangle.init(0, relY(0.94), WindowManager.getWindowWidth(), relH(0.06)), rl.Color.init(0, 0, 0, 60));
        logLineBgRect.draw();

        logText.value = Logger.getLatestLog();
        logText.draw();

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
