const std = @import("std");

const freetracer_lib = @import("freetracer-lib");

const Debug = freetracer_lib.Debug;
const c = freetracer_lib.c;

// const c = @import("../../lib/sys/system.zig").c;

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
        Debug.log(.ERROR, "Unable to obtain a matching dictionary for USB Device class.", .{});
        return error.FailedToObtainMatchingDictionary;
    }

    kernReturn = c.IOServiceGetMatchingServices(c.kIOMasterPortDefault, matchingDict, &ioIterator);

    if (kernReturn != c.KERN_SUCCESS) {
        Debug.log(.ERROR, "Unable to obtain matching services for the provided matching dictionary.", .{});
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

        // TODO: instead of registry entry name, query kUSBProductString property
        kernReturn = c.IORegistryEntryGetName(ioDevice, &deviceName);

        if (kernReturn != c.KERN_SUCCESS) {
            Debug.log(.ERROR, "Unable to obtain USB device name.", .{});
            continue;
        }

        Debug.log(.INFO, "Found device (service name in IO Registry): {s}\n", .{deviceName});

        //--- CHILD NODE PROPERTY ITERATION SECTION ----------------------------------
        //----------------------------------------------------------------------------
        getIOMediaVolumesForDevice(ioDevice, allocator, &deviceVolumesList) catch |err| {
            Debug.log(.ERROR, "Error occurred while fetching IOMedia volumes for an IOUSBDevice. {any}", .{err});
        };

        if (deviceVolumesList.items.len == 0) continue;

        usbDevices.append(.{
            .serviceId = ioDevice,
            .deviceName = deviceName,
            .ioMediaVolumes = deviceVolumesList.clone() catch |err| {
                Debug.log(.ERROR, "Unable to deep-copy the devicesVolumesList <ArrayList(MacOS.IOMediaVolume)>. Error message: {any}", .{err});
                continue;
            },
        }) catch |err| {
            Debug.log(.ERROR, "Unable to append item of type USBDevice to usbDevices ArrayList. Error message: {any}", .{err});
            continue;
        };

        //--- END -------------------------------------------------------------------------

    }

    if (usbDevices.items.len == 0) {
        Debug.log(.WARNING, "No USB media devices were found with IOMedia volumes.", .{});
        return error.FailedToObtainUSBDevicesWithIOMediaServices;
    }

    for (0..usbDevices.items.len) |i| {
        const usbDevice: MacOS.USBDevice = usbDevices.items[i];
        Debug.log(.INFO, "Processing USB Device with IOMedia volumes ({s} - {d})\n", .{ usbDevice.deviceName, usbDevice.serviceId });

        var usbStorageDevice: USBStorageDevice = .{
            .allocator = allocator,
            .volumes = std.ArrayList(MacOS.IOMediaVolume).init(allocator),
        };

        for (0..usbDevice.ioMediaVolumes.items.len) |v| {
            var ioMediaVolume: MacOS.IOMediaVolume = usbDevice.ioMediaVolumes.items[v];

            // TODO: This is a ToDo, not a note.
            // Make sure memory is cleaned up on every possible function exit (errors specifically!)
            errdefer ioMediaVolume.deinit();

            // Volume is the "parent" disk, e.g. the whole volume (disk4)
            // Cannot check ofr isLeaf here because devices with ISO burned onto them
            // have no leaf volumes and are themselves considered both whole AND leaf at the same time
            if (ioMediaVolume.isWhole and ioMediaVolume.isRemovable) {
                usbStorageDevice.serviceId = ioMediaVolume.serviceId;
                usbStorageDevice.size = ioMediaVolume.size;

                const deviceNameSlice = std.mem.sliceTo(&usbDevice.deviceName, 0x00);

                Debug.log(.INFO, "deviceNameSlice before array transformation is: {s}", .{deviceNameSlice});

                usbStorageDevice.deviceNameBuf = toArraySentinel(
                    @constCast(deviceNameSlice),
                    USBStorageDevice.kDeviceNameBufferSize,
                );

                usbStorageDevice.bsdNameBuf = toArraySentinel(
                    @constCast(ioMediaVolume.bsdNameBuf[0..ioMediaVolume.bsdNameBuf.len]),
                    USBStorageDevice.kDeviceBsdNameBufferSize,
                );

                Debug.log(.INFO, "USBStorageDevice:\n\tname: {s}\n\tbsdName: {s}", .{ usbStorageDevice.deviceNameBuf, usbStorageDevice.bsdNameBuf });

                // Volume is a Leaf scenario
            } else if (!ioMediaVolume.isWhole and ioMediaVolume.isLeaf and ioMediaVolume.isRemovable) {
                usbStorageDevice.volumes.append(ioMediaVolume) catch |err| {
                    Debug.log(.ERROR, "Failed to append IOMediaVolume to ArrayList<IOMediaVolume> within USBStorageDevice. Error message: {any}\n", .{err});
                    break;
                };
            }
        }

        usbStorageDevices.append(usbStorageDevice) catch |err| {
            Debug.log(.ERROR, "Failed to append USBStorageDevice to ArrayList<USBStorageDevice>. Error message: {any}\n", .{err});
            return error.FailedToAppendUSBStorageDevice;
        };

        Debug.log(.INFO, "\nDetected the following USB Storage Devices:\n", .{});
        for (usbStorageDevices.items) |*device| {
            device.print();
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
        Debug.log(.ERROR, "\nUnable to obtain child iterator for device's registry entry.", .{});
        return error.getIOMediaVolumesForDeviceIsUnableToObtainChildIterator;
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
                Debug.log(.ERROR, "(IOKit.getIOMediaVolumesForDevice): unable to append child service to volumes list. Error message: {any}", .{err});
            };
        }

        // TODO: Review options other than recursion. Could be theoretically dangerous to walk through the IORegistry recursively.
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

    const newBsdNameBuf = toArraySentinel(bsdNameBuf[0..bsdNameBuf.len], MacOS.IOMediaVolume.kVolumeBsdNameBufferSize);
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
        .bsdNameBuf = newBsdNameBuf,
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
        Debug.log(.ERROR, "toCString(): Failed to allocate heap memory for C string. Error message: {any}", .{err});
        return error.FailedToCreateCString;
    };

    for (0..string.len) |i| {
        cString[i] = string[i];
    }

    cString[string.len] = 0;

    return cString;
}

pub fn toSlice(string: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(string, 0);
}

fn toArraySentinel(slice: []u8, comptime size: usize) [size:0]u8 {
    var output: [size:0]u8 = comptime std.mem.zeroes([size:0]u8);
    const usefulSlice = std.mem.sliceTo(slice, 0x00);

    if (slice.len > size) {
        Debug.log(.WARNING, "toArraySentinel(): slice length [{d}] exceeds the buffer size [{d}]", .{ slice.len, size });
    }

    for (0..size) |i| {
        //
        if (i >= slice.len) {
            output[i] = 0x00;
            continue;
        } else {
            output[i] = slice[i];
        }

        if (i == usefulSlice.len) output[i] = 0x00;
    }

    Debug.log(.DEBUG, "toArraySentinel processed: {s}, {any}", .{ output, output });

    return output;
}
