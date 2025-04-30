const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const osd = @import("osdialog");

const Logger = @import("./lib/util/logger.zig").LoggerSingleton;

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");
const PrivilegedHelper = @import("modules/macos/PrivilegedHelper.zig");

const UI = @import("lib/ui/ui.zig");

const Checkbox = @import("lib/ui/Checkbox.zig").Checkbox();

const AppObserver = @import("observers/AppObserver.zig").AppObserver;

const Component = @import("components/Component.zig");
const ComponentID = @import("components/Registry.zig").ComponentID;
const ComponentRegistry = @import("components/Registry.zig").ComponentRegistry;

const FilePickerComponent = @import("components/FilePicker/Component.zig");
const USBDevicesListComponent = @import("components/USBDevicesList/Component.zig");

// const ArgValidator = struct {
//     isoPath: bool = false,
//     devicePath: bool = false,
// };

const WINDOW_WIDTH_FACTOR: f32 = 0.5;
const WINDOW_HEIGHT_FACTOR: f32 = 0.5;

var Window: UI.Window = .{
    .width = 0,
    .height = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    try Logger.init(allocator);
    errdefer Logger.deinit();
    defer Logger.deinit();

    rl.initWindow(Window.width, Window.height, "");
    defer rl.closeWindow(); // Close window and OpenGL context

    const m = rl.getCurrentMonitor();
    const mWidth = rl.getMonitorWidth(m);
    const mHeight = rl.getMonitorHeight(m);

    Window.width = @intFromFloat(@as(f32, @floatFromInt(mWidth)) * WINDOW_WIDTH_FACTOR);
    Window.height = @intFromFloat(@as(f32, @floatFromInt(mHeight)) * WINDOW_HEIGHT_FACTOR);

    debug.printf("\nWINDOW INITIALIZED: {d}x{d}\n", .{ Window.width, Window.height });

    rl.setWindowSize(Window.width, Window.height);
    rl.setWindowPosition(
        @as(i32, @divTrunc(mWidth, 2) - @divTrunc(Window.width, 2)),
        @as(i32, @divTrunc(mHeight, 2) - @divTrunc(Window.height, 2)),
    );

    // LOAD FONTS HERE

    rl.setTargetFPS(60);

    //--------------------------------------------------------------------------------------

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    //--- @COMPONENTS ----------------------------------------------------------------------

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

    //--- @ENDCOMPONENTS -------------------------------------------------------------------

    const isoRect: UI.Rect = .{
        .x = relW(0.08),
        .y = relH(0.2),
        .width = relW(0.35),
        .height = relH(0.7),
        .color = .{ .r = 248, .g = 135, .b = 255, .a = 17 },
    };

    const usbRect: UI.Rect = .{
        .x = isoRect.x + isoRect.width + relW(0.02),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .{ .r = 91, .g = 130, .b = 149, .a = 100 },
    };

    const flashRect: UI.Rect = .{
        .x = usbRect.x + usbRect.width + relW(0.02),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .{ .r = 47, .g = 102, .b = 77, .a = 100 },
    };

    var helperResponse: bool = false;
    helperResponse = true;
    // if (!PrivilegedHelper.isHelperToolInstalled()) {
    // helperResponse = PrivilegedHelper.installPrivilegedHelperTool();
    // if (helperResponse) helperResponse = PrivilegedHelper.performPrivilegedTask(disk);
    // } else helperResponse = true;

    // Main application GUI.loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        //--- @UPDATE ----------------------------------------------------------------------
        componentRegistry.processUpdates();
        //--- @ENDUPDATE -------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @DRAW ------------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        rl.beginDrawing();

        rl.clearBackground(backgroundColor);

        isoRect.draw();
        usbRect.draw();
        flashRect.draw();

        rl.drawText("freetracer", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035)), 22, .white);
        rl.drawText("free and open-source by orbitixx", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035) + 23), 14, .light_gray);

        rl.drawText(
            if (helperResponse) "HELPER SUCCESS" else "HELPER FAILED",
            @intFromFloat(relW(0.86)),
            @intFromFloat(relH(0.035)),
            12,
            if (helperResponse) .green else .red,
        );

        rl.drawText(
            Logger.getLatestLog(),
            @intFromFloat(relW(0.02)),
            @intFromFloat(relH(0.95)),
            13,
            .white,
        );

        componentRegistry.processRendering();

        defer rl.endDrawing();
        //--- @ENDDRAW----------------------------------------------------------------------

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

pub fn relW(x: f32) f32 {
    return (@as(f32, @floatFromInt(Window.width)) * x);
}

pub fn relH(y: f32) f32 {
    return (@as(f32, @floatFromInt(Window.height)) * y);
}
