const std = @import("std");
const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const rl = @import("raylib");
const ui = @import("lib/ui/ui.zig");
const osd = @import("osdialog");

const isMac = @import("builtin").os.tag == .macos;
const isLinux = @import("buildin").os.tag == .linux;

const c = if (isMac) @cImport({
    @cInclude("IOKit/storage/IOMedia.h");
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("IOKit/usb/USB.h");
    @cInclude("IOKit/usb/IOUSBLib.h");
    @cInclude("IOKit/IOCFPlugIn.h");
}) else if (isLinux) @cImport({
    @cInclude("blkid/blkid.h");
});

const assert = std.debug.assert;

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");

const ArgValidator = struct {
    isoPath: bool = false,
    devicePath: bool = false,
};

const SCREEN_WIDTH = 850;
const SCREEN_HEIGHT = 500;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    // var devDir = try std.fs.openDirAbsolute("/dev", .{ .iterate = true });
    // defer devDir.close();
    //
    // const dirStat = try devDir.stat();
    //
    // var dirIterator = devDir.iterate();
    //
    // debug.printf("\n:: Freetracer: found the following disks {d}: ", .{dirStat.size});
    //
    // while (try dirIterator.next()) |dirEntry| {
    //     if (dirEntry.kind == .block_device and std.mem.startsWith(u8, dirEntry.name, "disk")) {
    //         debug.printf("\n[DISK] {s}", .{dirEntry.name});
    //     }
    // }

    // try IsoWriter.write("/Users/cerberus/Documents/Projects/freetracer/alpine.iso", "/dev/disk4");

    // const disk = try std.fs.openFileAbsolute("/dev/disk4", .{ .mode = .read_only });
    // defer disk.close();
    //
    // const diskStat = try disk.stat();
    // debug.printf("\nDisk4 size is: {d}\n", .{diskStat.size});
    //

    macOS_listUSBDevices();

    _ = allocator;

    // const args = try std.process.argsAlloc(allocator);
    // defer std.process.argsFree(allocator, args);
    //
    // debug.printf("\nTotal process arguments: {d}\n", .{args.len});
    //
    // rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "");
    // defer rl.closeWindow(); // Close window and OpenGL context
    // //
    // const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };
    //
    // rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    // //--------------------------------------------------------------------------------------

    //
    // const isoRect: ui.Rect = .{
    //     .x = relW(0.08),
    //     .y = relH(0.2),
    //     .width = relW(0.35),
    //     .height = relH(0.7),
    //     .color = .fade(.light_gray, 0.3),
    // };
    //
    // const usbRect: ui.Rect = .{
    //     .x = isoRect.x + isoRect.width + relW(0.08),
    //     .y = relH(0.2),
    //     .width = relW(0.175),
    //     .height = relH(0.7),
    //     .color = .fade(.light_gray, 0.3),
    // };
    //
    // const flashRect: ui.Rect = .{
    //     .x = usbRect.x + usbRect.width + relW(0.08),
    //     .y = relH(0.2),
    //     .width = relW(0.175),
    //     .height = relH(0.7),
    //     .color = .fade(.light_gray, 0.3),
    // };
    //
    // var isoPath: ?[]u8 = null;
    //
    // var isoBtn = ui.Button().init(allocator, &isoPath, "Select ISO...", relW(0.12), relH(0.35), 14, .white, .red);
    //
    // // Main application GUI loop
    // while (!rl.windowShouldClose()) { // Detect window close button or ESC key
    //     // Update
    //     //----------------------------------------------------------------------------------
    //
    //     //----------------------------------------------------------------------------------
    //
    //     // Draw
    //     //----------------------------------------------------------------------------------
    //     rl.beginDrawing();
    //     defer rl.endDrawing();
    //
    //     rl.clearBackground(backgroundColor);
    //
    //     isoRect.draw();
    //     usbRect.draw();
    //     flashRect.draw();
    //
    //     isoBtn.draw();
    //     isoBtn.events();
    //
    //     rl.drawText("freetracer", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035)), 22, .white);
    //     rl.drawText("free and open-source by orbitixx", @intFromFloat(relW(0.08)), @intFromFloat(relH(0.035) + 23), 14, .light_gray);
    //     //----------------------------------------------------------------------------------
    //
    //     if (isoPath) |path| {
    //         debug.printf("\n\nReceived path: {s}", .{path});
    //         defer allocator.free(path);
    //
    //         try IsoParser.parseIso(&allocator, path);
    //         try IsoWriter.write(path, "/dev/sdb");
    //
    //         break;
    //     }
    // }

    // var argValidator = ArgValidator{};
    //
    // var devicePath: []u8 = undefined;
    //
    // const ISO_ARG = "--iso";
    // const DEVICE_ARG = "--device";
    //
    // for (1..(args.len - 1)) |i| {
    //     assert(args[i + 1].len != 0);
    //
    //     if (strings.eql(args[i], ISO_ARG)) {
    //         isoPath = args[i + 1];
    //         argValidator.isoPath = true;
    //     } else if (strings.eql(args[i], DEVICE_ARG)) {
    //         devicePath = args[i + 1];
    //         argValidator.devicePath = true;
    //     }
    // }
    //
    // debug.printf("\n--iso: {s}\n--device: {s}", .{ isoPath, devicePath });
    //
    // assert(argValidator.isoPath == true and argValidator.devicePath == true);
    //
    // try IsoParser.parseIso(&allocator, isoPath);
    // try IsoWriter.write(isoPath, devicePath);
    //
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/alpine.iso");
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/tinycore.iso");

    debug.print("\n");
}

pub fn relW(x: f32) f32 {
    return (SCREEN_WIDTH * x);
}

pub fn relH(y: f32) f32 {
    return (SCREEN_HEIGHT * y);
}

pub fn macOS_listUSBDevices() void {
    var matchingDict: c.CFMutableDictionaryRef = null;
    var ioIterator: c.io_iterator_t = 0;
    var kernReturn: ?c.kern_return_t = null;
    var device: c.io_service_t = 0;

    matchingDict = c.IOServiceMatching(c.kIOUSBDeviceClassName);

    if (matchingDict == null) {
        debug.print("\nERROR: Unable to obtain a matching dictionary for USB Device class.");
        return;
    }

    kernReturn = c.IOServiceGetMatchingServices(c.kIOMasterPortDefault, matchingDict, &ioIterator);

    if (kernReturn != c.KERN_SUCCESS) {
        debug.print("\nERROR: Unable to obtain matching services for the provided matching dictionary.");
        return;
    }

    device = c.IOIteratorNext(ioIterator);

    while (device != 0) {
        var deviceName: c.io_name_t = undefined;

        kernReturn = c.IORegistryEntryGetName(device, &deviceName);

        if (kernReturn != c.KERN_SUCCESS) {
            debug.print("\nERROR: Unable to obtain USB device name.");
        } else {
            debug.printf("\nDEVICE: {s}", .{deviceName});
        }

        _ = c.IOObjectRelease(device);
        device = c.IOIteratorNext(ioIterator);
    }

    defer _ = c.IOObjectRelease(ioIterator);
}
