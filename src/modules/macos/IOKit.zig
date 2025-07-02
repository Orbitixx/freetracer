const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const c = @import("../../lib/sys/system.zig").c;

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const MacOS = @import("MacOSTypes.zig");

/// TODO: needs refactoring - useless work being done to get to a list of IOMediaVolumes
pub fn getUSBStorageDevices(allocator: std.mem.Allocator) !std.ArrayList(USBStorageDevice) {
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

    var usbDevices = std.ArrayList(MacOS.USBDevice).init(allocator);
    defer usbDevices.deinit();

    var usbStorageDevices = std.ArrayList(USBStorageDevice).init(allocator);

    while (ioDevice != 0) {

        //--- OBTAIN PARENT DEVICE NODE SECTION --------------------------------------
        //----------------------------------------------------------------------------

        ioDevice = c.IOIteratorNext(ioIterator);

        if (ioDevice == 0) break;

        defer _ = c.IOObjectRelease(ioDevice);

        var deviceName: c.io_name_t = undefined;
        var deviceVolumesList = std.ArrayList(MacOS.IOMediaVolume).init(allocator);
        defer deviceVolumesList.deinit();

        kernReturn = c.IORegistryEntryGetName(ioDevice, &deviceName);

        if (kernReturn != c.KERN_SUCCESS) {
            debug.print("\nERROR: Unable to obtain USB device name.");
            continue;
        }

        debug.printf("\nFound device (service name in IO Registry): {s}\n", .{deviceName});

        //--- CHILD NODE PROPERTY ITERATION SECTION ----------------------------------
        //----------------------------------------------------------------------------
        getIOMediaVolumesForDevice(ioDevice, allocator, &deviceVolumesList) catch |err| {
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

        var usbStorageDevice: USBStorageDevice = .{
            .allocator = allocator,
            .volumes = std.ArrayList(MacOS.IOMediaVolume).init(allocator),
        };

        for (0..usbDevice.ioMediaVolumes.items.len) |v| {
            var ioMediaVolume: MacOS.IOMediaVolume = usbDevice.ioMediaVolumes.items[v];

            // Need to re-allocate the bsdName slice, otherwise the lifespan of the old slice is cleaned up too soon
            ioMediaVolume.bsdName = allocator.dupe(u8, usbDevice.ioMediaVolumes.items[v].bsdName) catch |err| {
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

                usbStorageDevice.deviceName = allocator.dupe(u8, deviceNameSlice) catch |err| {
                    debug.printf("\nERROR: Failed to duplicate Device Name from USBDevice to USBStorageDevice. Error message: {any}", .{err});
                    break;
                };

                usbStorageDevice.bsdName = allocator.dupe(u8, ioMediaVolume.bsdName) catch |err| {
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
            const dev: USBStorageDevice = usbStorageDevices.items[d];
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

pub fn getIOMediaVolumesForDevice(device: c.io_service_t, allocator: std.mem.Allocator, pVolumesList: *std.ArrayList(MacOS.IOMediaVolume)) !void {
    var kernReturn: ?c.kern_return_t = null;
    var childService: c.io_service_t = 1;
    var childIterator: c.io_iterator_t = 0;

    kernReturn = c.IORegistryEntryGetChildIterator(device, c.kIOServicePlane, &childIterator);

    if (kernReturn != c.KERN_SUCCESS) {
        debug.print("\nUnable to obtain child iterator for device's registry entry.");
    }

    while (childService != 0) {
        childService = c.IOIteratorNext(childIterator);
        if (childService == 0) break;
        defer _ = c.IOObjectRelease(childService);

        const ioMediaCString = "IOMedia";
        const isIOMedia: bool = c.IOObjectConformsTo(childService, ioMediaCString) != 0;

        if (isIOMedia) {
            const ioMediaVolume = try getIOMediaVolumeDescription(childService, allocator);

            pVolumesList.*.append(ioMediaVolume) catch |err| {
                debug.printf("\nERROR (IOKit.getIOMediaVolumesForDevice): unable to append child service to volumes list. Error message: {any}", .{err});
            };
        }

        // TODO: Review options other than recursion. Could be theoretically dangeroues to walk through the IORegistry recursively.
        // While the IORegirsty is a finite tree, a memory-safe alternative would be preferable.
        try getIOMediaVolumesForDevice(childService, allocator, pVolumesList);
    }

    defer _ = c.IOObjectRelease(childIterator);
}

pub fn getIOMediaVolumeDescription(service: c.io_service_t, allocator: std.mem.Allocator) !MacOS.IOMediaVolume {

    //--- @prop: BSDName (String) --------------------------------------------------------
    //------------------------------------------------------------------------------------
    const bsdNameKey: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOBSDNameKey, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(bsdNameKey);

    const bsdNameValueRef: c.CFStringRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, bsdNameKey, c.kCFAllocatorDefault, 0));
    if (bsdNameValueRef == null) return error.FailedToObtainBSDNameForVolume;
    defer _ = c.CFRelease(bsdNameValueRef);
    var bsdNameBuf: [128]u8 = undefined;

    _ = c.CFStringGetCString(bsdNameValueRef, &bsdNameBuf, bsdNameBuf.len, c.kCFStringEncodingUTF8);

    // bsdNameBuf is a stack-allocated buffer, which is erased when function exits,
    // therefore the string must be saved on the heap and cleaned up later.
    const heapBsdName = try allocator.alloc(u8, bsdNameBuf.len);
    @memcpy(heapBsdName, &bsdNameBuf);
    //--- @endprop -----------------------------------------------------------------------

    //--- @prop: Leaf (Bool) -------------------------------------------------------------
    const isLeaf: bool = try getBoolFromIOService(service, c.kIOMediaLeafKey);

    //--- @prop: Whole (Bool) ------------------------------------------------------------
    const isWhole: bool = try getBoolFromIOService(service, c.kIOMediaWholeKey);

    //--- @prop: isRemovable (Bool) ------------------------------------------------------
    const isRemovable: bool = try getBoolFromIOService(service, c.kIOMediaRemovableKey);

    //--- @prop: isOpen (Bool) ------------------------------------------------------
    const isOpen: bool = try getBoolFromIOService(service, c.kIOMediaOpenKey);

    //--- @prop: isWriteable (Bool) ------------------------------------------------------
    const isWritable: bool = try getBoolFromIOService(service, c.kIOMediaWritableKey);

    //--- @prop: Size (Number) -----------------------------------------------------------
    const mediaSizeInBytes: i64 = try getNumberFromIOService(i64, service, c.kIOMediaSizeKey);

    return .{
        .allocator = allocator,
        .serviceId = service,
        .bsdName = heapBsdName,
        .size = mediaSizeInBytes,
        .isLeaf = isLeaf,
        .isWhole = isWhole,
        .isRemovable = isRemovable,
        .isOpen = isOpen,
        .isWritable = isWritable,
    };
}

pub fn getBoolFromIOService(service: c.io_service_t, key: [*:0]const u8) !bool {
    const keyCString = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, key, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(keyCString);

    const keyValueRef: c.CFBooleanRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, keyCString, c.kCFAllocatorDefault, 0));

    if (keyValueRef == null or c.CFGetTypeID(keyValueRef) != c.CFBooleanGetTypeID()) return error.FailedToObtainCFBooleanRefForKey;
    defer _ = c.CFRelease(keyValueRef);

    const resultBool: bool = (keyValueRef == c.kCFBooleanTrue);

    return resultBool;
}

pub fn getNumberFromIOService(comptime T: type, service: c.io_service_t, key: [*:0]const u8) !T {
    const keyCString = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, key, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(keyCString);

    const keyValueRef: c.CFNumberRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, keyCString, c.kCFAllocatorDefault, 0));

    if (keyValueRef == null or c.CFGetTypeID(keyValueRef) != c.CFNumberGetTypeID()) return error.FailedToObtainCFNumberForKey;
    defer _ = c.CFRelease(keyValueRef);

    var result: T = 0;

    if (c.CFNumberGetValue(keyValueRef, c.kCFNumberLongLongType, &result) != 1) return error.FailedToExtractValueFromCFNumberRef;

    return result;
}

pub fn toCString(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
    if (string.len == 0) return error.OriginalStringMustBeNonZeroLength;

    var cString: []u8 = allocator.alloc(u8, string.len + 1) catch |err| {
        debug.printf("\nERROR (toCString()): Failed to allocate heap memory for C string. Error message: {any}", .{err});
        return error.FailedToCreateCString;
    };

    for (0..string.len) |i| {
        cString[i] = string[i];
    }

    cString[string.len] = 0;

    // return @ptrCast(cString);
    return cString;
}

pub fn toSlice(string: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(string, 0);
}
