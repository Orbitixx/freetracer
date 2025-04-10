const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const rl = @import("raylib");
const osd = @import("osdialog");
const ui = @import("lib/ui/ui.zig");

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");
const MacOS = @import("modules/macos/MacOSTypes.zig");
const IOKit = @import("modules/macos/IOKit.zig");
const DiskArbitration = @import("modules/macos/DiskArbitration.zig");

const ArgValidator = struct {
    isoPath: bool = false,
    devicePath: bool = false,
};

const SCREEN_WIDTH = 850;
const SCREEN_HEIGHT = 500;

const ISOFileState = struct {
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    taskRunning: bool = false,
    taskDone: bool = false,
    taskError: ?anyerror = null,

    isoPath: ?[]const u8 = null,

    pub fn deinit(self: ISOFileState) void {
        if (self.isoPath != null)
            self.allocator.free(self.isoPath.?);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "");
    defer rl.closeWindow(); // Close window and OpenGL context

    // LOAD FONTS HERE

    rl.setTargetFPS(60);
    //--------------------------------------------------------------------------------------

    var isoFileState: ISOFileState = .{
        .allocator = allocator,
    };
    defer isoFileState.deinit();

    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    const isoRect: ui.Rect = .{
        .x = relW(0.08),
        .y = relH(0.2),
        .width = relW(0.35),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    const usbRect: ui.Rect = .{
        .x = isoRect.x + isoRect.width + relW(0.08),
        .y = relH(0.2),
        .width = relW(0.175),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    const flashRect: ui.Rect = .{
        .x = usbRect.x + usbRect.width + relW(0.08),
        .y = relH(0.2),
        .width = relW(0.175),
        .height = relH(0.7),
        .color = .fade(.light_gray, 0.3),
    };

    var isoPath: ?[]u8 = null;

    var isoBtn = ui.Button().init(allocator, &isoPath, "Select ISO...", relW(0.12), relH(0.35), 14, .white, .red);
    defer isoBtn.deinit();

    // Main application GUI loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        //--- @UPDATE ----------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        if (isoPath) |path| {
            isoFileState.mutex.lock();
            const isoPathState = isoFileState.isoPath != null;
            isoFileState.mutex.unlock();

            if (!isoPathState) {
                debug.printf("\n\nReceived ISO path: {s}", .{path});

                isoFileState.mutex.lock();
                isoFileState.isoPath = isoFileState.allocator.dupe(u8, path) catch blk: {
                    debug.print("\nERROR: Unable to duplicate isoPath to the ISOFileState member.");
                    break :blk null;
                };
                isoFileState.mutex.unlock();

                allocator.free(isoPath.?);
                isoPath = null;
            }
        }

        //--- @ENDUPDATE -------------------------------------------------------------------

        //----------------------------------------------------------------------------------
        //--- @DRAW ------------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(backgroundColor);

        isoRect.draw();
        usbRect.draw();
        flashRect.draw();

        isoBtn.draw();
        isoBtn.events();

        rl.drawText("freetracer", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035)), 22, .white);
        rl.drawText("free and open-source by orbitixx", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035) + 23), 14, .light_gray);
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
    return (SCREEN_WIDTH * x);
}

pub fn relH(y: f32) f32 {
    return (SCREEN_HEIGHT * y);
}
