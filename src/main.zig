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
    @cInclude("IOKit/IOBSD.h");
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

// Define a callback
fn unmountCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    _ = disk;
    _ = context;

    if (dissenter == null) {
        debug.print("\nDisk unmount successful!\n");
    } else {
        const status = c.DADissenterGetStatus(dissenter);
        debug.printf("\nUnmount failed with status: {any}.\n", .{status});
        return;
    }
}

pub fn macOS_listUSBDevices() void {
    var matchingDict: c.CFMutableDictionaryRef = null;
    var ioIterator: c.io_iterator_t = 0;
    var kernReturn: ?c.kern_return_t = null;
    var device: c.io_service_t = 0;

    matchingDict = c.IOServiceMatching(c.kIOUSBDeviceClassName);
    // defer _ = c.CFRelease(matchingDict);

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

        //--- OBTAIN PARENT DEVICE NODE SECTION --------------------------------------
        //----------------------------------------------------------------------------
        defer _ = c.IOObjectRelease(device);

        var deviceName: c.io_name_t = undefined;

        kernReturn = c.IORegistryEntryGetName(device, &deviceName);

        if (kernReturn != c.KERN_SUCCESS) {
            debug.print("\nERROR: Unable to obtain USB device name.");
            device = c.IOIteratorNext(ioIterator);
            continue;
        }

        debug.printf("\nFound device (service name in IO Registry): {s}", .{deviceName});

        var stringBuffer: [128]u8 = undefined;

        const kIOBSDNameKey: c.CFStringRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOBSDNameKey, c.kCFStringEncodingUTF8);
        defer _ = c.CFRelease(kIOBSDNameKey);

        const deviceBSDName_cf: c.CFStringRef = @ptrCast(c.IORegistryEntrySearchCFProperty(device, c.kIOServicePlane, kIOBSDNameKey, c.kCFAllocatorDefault, c.kIORegistryIterateRecursively));
        defer _ = c.CFRelease(deviceBSDName_cf);

        _ = c.CFStringGetCString(deviceBSDName_cf, &stringBuffer, stringBuffer.len, c.kCFStringEncodingUTF8);

        debug.printf("\nDevice path: {s}", .{stringBuffer});

        const session = c.DASessionCreate(c.kCFAllocatorDefault);
        if (session == null) {
            debug.print("\nFailed to create DA session\n");
            return;
        }

        // c.CFStringGetCStringPtr(deviceBSDName_cf, c.kCFStringEncodingUTF8)

        // const cfBsdName = c.CFStringCreateWithCString(c.kCFAllocatorDefault, deviceBSDName_cf, c.kCFStringEncodingUTF8);
        const disk: c.DADiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, session, "disk4");

        if (disk == null) {
            debug.print("\nFailed to create DA disk\n");
            return;
        }

        // Call the unmount function
        c.DADiskUnmount(disk, c.kDADiskUnmountOptionDefault, unmountCallback, null);

        // Run the runloop to allow async callback to fire
        c.CFRunLoopRun();

        // const kIOBootDeviceSizeKey: c.CFStringRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOMaximumByteCountReadKey, c.kCFStringEncodingUTF8);
        // defer _ = c.CFRelease(kIOBootDeviceSizeKey);
        //
        // const deviceSize_cf: c.CFStringRef = @ptrCast(c.IORegistryEntrySearchCFProperty(device, c.kIOServicePlane, kIOBootDeviceSizeKey, c.kCFAllocatorDefault, c.kIORegistryIterateRecursively));
        // defer _ = c.CFRelease(deviceSize_cf);
        //
        // stringBuffer = undefined;
        //
        // _ = c.CFStringGetCString(deviceSize_cf, &stringBuffer, stringBuffer.len, c.kCFStringEncodingUTF8);
        //
        // debug.printf("\nDevice size: {s}", .{stringBuffer});

        //----------------------------------------------------------------------------

        //--- CHILD NODE PROPERTY ITERATION SECTION ----------------------------------
        //----------------------------------------------------------------------------

        // var childIterator: c.io_iterator_t = 0;
        // var childNode: c.io_service_t = 0;
        //
        // kernReturn = c.IORegistryEntryGetChildIterator(device, c.kIOServicePlane, &childIterator);
        // defer _ = c.IOObjectRelease(childIterator);
        //
        // if (kernReturn != c.KERN_SUCCESS) {
        //     debug.print("\nUnable to obtain child iterator for device's registry entry.");
        //     device = c.IOIteratorNext(ioIterator);
        //     continue;
        // }
        //
        // childNode = c.IOIteratorNext(childIterator);
        //
        // while (childIterator != 0) {
        //     const wholeString: c.CFStringRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, "Whole", c.kCFStringEncodingUTF8);
        //     defer _ = c.CFRelease(wholeString);
        //
        //     const isWhole: c.CFBooleanRef = @ptrCast(c.IORegistryEntryCreateCFProperty(childNode, wholeString, c.kCFAllocatorDefault, 0));
        //     defer _ = c.CFRelease(isWhole);
        //
        //     if (isWhole != null) {
        //         debug.printf("\nisWhole: {any}", .{c.CFBooleanGetValue(isWhole)});
        //     }
        //
        //     childNode = c.IOIteratorNext(childIterator);
        // }

        //--- END CHILD NODE PROPERTY ITERATION SECTION -------------------------------

        device = c.IOIteratorNext(ioIterator);
    }

    defer _ = c.IOObjectRelease(ioIterator);
}
