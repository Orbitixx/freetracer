const std = @import("std");
const c = @import("lib/sys/system.zig").c;

const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");

const rl = @import("raylib");
const ui = @import("lib/ui/ui.zig");
const osd = @import("osdialog");

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
    //

    const usbStorageDevices = macOS_getUSBStorageDevices(&allocator) catch blk: {
        debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
        break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    };

    defer usbStorageDevices.deinit();

    if (usbStorageDevices.items.len > 0) {
        if (std.mem.count(u8, usbStorageDevices.items[0].bsdName, "disk4") > 0) {
            debug.print("\nFound disk4 by literal. Preparing to unmount...");
            DiskArbitration.unmountAllVolumes(&usbStorageDevices.items[0]) catch |err| {
                debug.printf("\nERROR: Failed to unmount volumes on {s}. Error message: {any}", .{ usbStorageDevices.items[0].bsdName, err });
            };
        }
    }

    defer {
        for (usbStorageDevices.items) |usbStorageDevice| {
            usbStorageDevice.deinit();
        }
    }

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

pub fn macOS_getUSBStorageDevices(pAllocator: *const std.mem.Allocator) !std.ArrayList(MacOS.USBStorageDevice) {
    var matchingDict: c.CFMutableDictionaryRef = null;
    var ioIterator: c.io_iterator_t = 0;
    var kernReturn: ?c.kern_return_t = null;
    var ioDevice: c.io_service_t = 1;

    matchingDict = c.IOServiceMatching(c.kIOUSBDeviceClassName);

    if (matchingDict == null) {
        debug.print("\nERROR: Unable to obtain a matching dictionary for USB Device class.");
        return error.FailedToObtainMatchingDictionary;
    }

    kernReturn = c.IOServiceGetMatchingServices(c.kIOMasterPortDefault, matchingDict, &ioIterator);

    if (kernReturn != c.KERN_SUCCESS) {
        debug.print("\nERROR: Unable to obtain matching services for the provided matching dictionary.");
        return error.FailedToObtainUSBServicesFromIORegistry;
    }

    var usbDevices = std.ArrayList(MacOS.USBDevice).init(pAllocator.*);
    defer usbDevices.deinit();

    var usbStorageDevices = std.ArrayList(MacOS.USBStorageDevice).init(pAllocator.*);

    while (ioDevice != 0) {

        //--- OBTAIN PARENT DEVICE NODE SECTION --------------------------------------
        //----------------------------------------------------------------------------

        ioDevice = c.IOIteratorNext(ioIterator);

        if (ioDevice == 0) break;

        defer _ = c.IOObjectRelease(ioDevice);

        var deviceName: c.io_name_t = undefined;
        var deviceVolumesList = std.ArrayList(MacOS.IOMediaVolume).init(pAllocator.*);
        defer deviceVolumesList.deinit();

        kernReturn = c.IORegistryEntryGetName(ioDevice, &deviceName);

        if (kernReturn != c.KERN_SUCCESS) {
            debug.print("\nERROR: Unable to obtain USB device name.");
            continue;
        }

        debug.printf("\nFound device (service name in IO Registry): {s}\n", .{deviceName});

        //--- CHILD NODE PROPERTY ITERATION SECTION ----------------------------------
        //----------------------------------------------------------------------------
        IOKit.getIOMediaVolumesForDevice(ioDevice, pAllocator, &deviceVolumesList) catch |err| {
            debug.printf("\n{any}", .{err});
        };

        if (deviceVolumesList.items.len == 0) continue;

        usbDevices.append(.{
            .serviceId = ioDevice,
            .deviceName = deviceName,
            .ioMediaVolumes = deviceVolumesList.clone() catch |err| {
                debug.printf("\nERROR: Unable to deep-copy the devicesVolumesList <ArrayList(MacOS.IOMediaVolume)>. Error message: {any}", .{err});
                continue;
            },
        }) catch |err| {
            debug.printf("\nERROR: Unable to append item of type USBDevice to usbDevices ArrayList. Error message: {any}", .{err});
            continue;
        };

        //--- END -------------------------------------------------------------------------

    }

    if (usbDevices.items.len == 0) {
        debug.print("\nWARNING: No USB media devices were found with IOMedia volumes.");
        return error.FailedToObtainUSBDevicesWithIOMediaServices;
    }

    for (0..usbDevices.items.len) |i| {
        const usbDevice: MacOS.USBDevice = usbDevices.items[i];
        debug.printf("\nUSB Device with IOMedia volumes ({s} - {d})\n", .{ usbDevice.deviceName, usbDevice.serviceId });

        var usbStorageDevice: MacOS.USBStorageDevice = .{
            .pAllocator = pAllocator,
            .volumes = std.ArrayList(MacOS.IOMediaVolume).init(pAllocator.*),
        };

        for (0..usbDevice.ioMediaVolumes.items.len) |v| {
            var ioMediaVolume: MacOS.IOMediaVolume = usbDevice.ioMediaVolumes.items[v];

            // Need to re-allocate the bsdName slice, otherwise the lifespan of the old slice is cleaned up too soon
            ioMediaVolume.bsdName = pAllocator.*.dupe(u8, usbDevice.ioMediaVolumes.items[v].bsdName) catch |err| {
                debug.printf("\nERROR: Ran out of memory attempting to allocate IOMediaVolume BSDName. Error message: {any}", .{err});
                return error.FailedToAllocateBSDNameMemoryDuringCopy;
            };

            // TODO: Make sure memory is cleaned up on every possible function exit (errors specifically!)

            errdefer ioMediaVolume.deinit();

            // Volume is the "parent" disk, e.g. the whole volume (disk4)
            if (ioMediaVolume.isWhole and !ioMediaVolume.isLeaf and ioMediaVolume.isRemovable) {
                // Important to realease memory in this exit scenario
                defer ioMediaVolume.deinit();

                usbStorageDevice.serviceId = ioMediaVolume.serviceId;
                usbStorageDevice.size = ioMediaVolume.size;

                const deviceNameSlice = std.mem.sliceTo(&usbDevice.deviceName, 0);

                usbStorageDevice.deviceName = pAllocator.*.dupe(u8, deviceNameSlice) catch |err| {
                    debug.printf("\nERROR: Failed to duplicate Device Name from USBDevice to USBStorageDevice. Error message: {any}", .{err});
                    break;
                };

                usbStorageDevice.bsdName = pAllocator.*.dupe(u8, ioMediaVolume.bsdName) catch |err| {
                    debug.printf("\nERROR: Failed to duplicate BSDName from USBDevice to USDStorageDevice. Error message: {any}", .{err});
                    break;
                };

                // Volume is a Leaf scenario
            } else if (!ioMediaVolume.isWhole and ioMediaVolume.isLeaf and ioMediaVolume.isRemovable) {
                usbStorageDevice.volumes.append(ioMediaVolume) catch |err| {
                    debug.printf("\nERROR: Failed to append IOMediaVolume to ArrayList<IOMediaVolume> within USBStorageDevice. Error message: {any}\n", .{err});
                    break;
                };
            }
        }

        usbStorageDevices.append(usbStorageDevice) catch |err| {
            debug.printf("\nERROR: Failed to append USBStorageDevice to ArrayList<USBStorageDevice>. Error message: {any}\n", .{err});
        };

        debug.print("\nDetected the following USB Storage Devices:\n");
        for (0..usbStorageDevices.items.len) |d| {
            const dev: MacOS.USBStorageDevice = usbStorageDevices.items[d];
            dev.print();
        }
    }

    defer {
        for (usbDevices.items) |usbDevice| {
            usbDevice.deinit();
        }
    }

    defer _ = c.IOObjectRelease(ioIterator);

    return usbStorageDevices;
}
