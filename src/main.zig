const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const rg = @import("raygui");
const osd = @import("osdialog");

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");

const UI = @import("lib/ui/ui.zig");

const Checkbox = @import("lib/ui/Checkbox.zig").Checkbox();

const AppObserver = @import("observers/AppObserver.zig").AppObserver;
const AppController = @import("AppController.zig");

const Component = @import("components/Component.zig");
const ComponentID = @import("components/Registry.zig").ComponentID;
const ComponentRegistry = @import("components/Registry.zig").ComponentRegistry;

const FilePickerComponent = @import("components/FilePicker/Component.zig");
const USBDevicesListComponent = @import("components/USBDevicesList/Component.zig");

// const ArgValidator = struct {
//     isoPath: bool = false,
//     devicePath: bool = false,
// };

const WINDOW_WIDTH = 850;
const WINDOW_HEIGHT = 500;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "");
    defer rl.closeWindow(); // Close window and OpenGL context

    // LOAD FONTS HERE

    rl.setTargetFPS(60);

    //--------------------------------------------------------------------------------------

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    //--- @COMPONENTS ----------------------------------------------------------------------

    var componentRegistry: ComponentRegistry = .{
        .components = std.AutoHashMap(ComponentID, Component).init(allocator),
    };
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
        .color = .fade(.light_gray, 0.3),
    };

    const usbRect: UI.Rect = .{
        .x = isoRect.x + isoRect.width + relW(0.04),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    const flashRect: UI.Rect = .{
        .x = usbRect.x + usbRect.width + relW(0.04),
        .y = relH(0.2),
        .width = relW(0.20),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

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
    return (WINDOW_WIDTH * x);
}

pub fn relH(y: f32) f32 {
    return (WINDOW_HEIGHT * y);
}
