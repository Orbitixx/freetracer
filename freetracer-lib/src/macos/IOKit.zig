const std = @import("std");
const c = @import("../types.zig").c;
const Debug = @import("../util/debug.zig");
const Character = @import("../constants.zig").Character;

pub const MAX_BSD_NAME: usize = 64;
pub const MAX_DEVICE_NAME: usize = std.fs.max_name_bytes;

pub const StorageDevice = struct {
    serviceId: c.io_service_t,
    deviceName: [std.fs.max_name_bytes:0]u8,
    bsdName: [MAX_BSD_NAME:0]u8,
    size: i64,

    pub fn print(self: *const StorageDevice) void {
        Debug.log(.INFO, "Storage Device: {s} ({s}) - Size: {d} bytes", .{ self.deviceName, self.bsdName, self.size });
    }
};

fn getBoolFromIOService(service: c.io_service_t, key: [*c]const u8) !bool {
    const keyRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(keyRef);

    const valueRef = c.IORegistryEntryCreateCFProperty(service, keyRef, c.kCFAllocatorDefault, 0);
    if (valueRef == null) return error.FailedToGetBoolFromIOService;
    defer _ = c.CFRelease(valueRef);

    const boolRef: c.CFBooleanRef = @ptrCast(valueRef);
    return c.CFBooleanGetValue(boolRef) != 0;
}

fn getStringFromIOService(service: c.io_service_t, key: [*c]const u8, comptime size: usize) ![size:0]u8 {
    const stringNameKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(stringNameKey);

    const stringNameRef = c.IORegistryEntryCreateCFProperty(service, stringNameKey, c.kCFAllocatorDefault, 0);
    if (stringNameRef == null) return error.FailedToGetStringFromIOService;
    defer _ = c.CFRelease(stringNameRef);

    var stringNameBuf: [size:0]u8 = std.mem.zeroes([size:0]u8);
    const stringNameCFString: c.CFStringRef = @ptrCast(stringNameRef);

    if (c.CFStringGetCString(stringNameCFString, &stringNameBuf, size, c.kCFStringEncodingUTF8) == 0) {
        return error.FailedToConvertStringFromIOService;
    }

    return stringNameBuf;
}

fn getNumberFromIOService(service: c.io_service_t, key: [*c]const u8, numberType: c_int, comptime zigType: type) !i64 {
    const numberNameKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(numberNameKey);

    const numberKeyRef = c.IORegistryEntryCreateCFProperty(service, numberNameKey, c.kCFAllocatorDefault, 0);
    if (numberKeyRef == null) return error.FailedToGetNumberFromIOService;
    defer _ = c.CFRelease(numberKeyRef);

    const numberCFNumRef: c.CFNumberRef = @ptrCast(numberKeyRef);
    var numberValue: zigType = 0;

    if (c.CFNumberGetValue(numberCFNumRef, numberType, &numberValue) == 0) return error.FailedToConvertNumberFromIOService;

    return numberValue;
}

/// Helper function to copy C string to sentinel-terminated array
fn copyToSentinelArray(comptime size: usize, source: [*c]const u8, dest: *[size:0]u8) void {
    const sourceSlice = std.mem.span(source);
    const copyLength = @min(sourceSlice.len, size - 1);
    @memcpy(dest[0..copyLength], sourceSlice[0..copyLength]);
}

pub fn getStorageDevices(allocator: std.mem.Allocator) !std.ArrayList(StorageDevice) {
    var storageDevices = std.ArrayList(StorageDevice).init(allocator);

    const matchingDict = c.IOServiceMatching(c.kIOMediaClass);
    if (matchingDict == null) return error.FailedToCreateIOServiceMatchingDictionary;

    const isWholeKeyRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOMediaWholeKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(isWholeKeyRef);

    const isRemovableKeyRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOMediaRemovableKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(isRemovableKeyRef);

    const isEjectableKeyRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOMediaEjectableKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(isEjectableKeyRef);

    c.CFDictionarySetValue(matchingDict, isRemovableKeyRef, c.kCFBooleanTrue);
    c.CFDictionarySetValue(matchingDict, isWholeKeyRef, c.kCFBooleanTrue);
    c.CFDictionarySetValue(matchingDict, isEjectableKeyRef, c.kCFBooleanTrue);

    var serviceIterator: c.io_iterator_t = undefined;
    const kernReturn: c_int = c.IOServiceGetMatchingServices(c.kIOMasterPortDefault, matchingDict, &serviceIterator);

    if (kernReturn != c.KERN_SUCCESS) return error.FailedToGetMatchingServices;

    var currentService: c.io_service_t = c.IOIteratorNext(serviceIterator);

    while (currentService != 0) {
        const device = try getStorageDeviceFromService(currentService);
        try storageDevices.append(device);
        currentService = c.IOIteratorNext(serviceIterator);
    }

    return storageDevices;
}

fn getStorageDeviceFromService(service: c.io_service_t) !StorageDevice {
    const bsdName = try getStringFromIOService(service, c.kIOBSDNameKey, MAX_BSD_NAME);
    const bsdNameSlice = std.mem.sliceTo(&bsdName, Character.NULL);
    if (bsdNameSlice.len < 3) return error.BSDNameTooShort;

    const size: i64 = try getNumberFromIOService(service, c.kIOMediaSizeKey, c.kCFNumberSInt64Type, i64);

    var defaultDeviceName: [MAX_DEVICE_NAME:0]u8 = std.mem.zeroes([MAX_DEVICE_NAME:0]u8);
    @memcpy(defaultDeviceName[0..15], "Untitled Device");

    const deviceName: [MAX_DEVICE_NAME:0]u8 = try getVolumeNameFromBSDName(bsdNameSlice) orelse defaultDeviceName;

    return StorageDevice{
        .serviceId = service,
        .bsdName = bsdName,
        .size = size,
        .deviceName = deviceName,
    };
}

fn getVolumeNameFromBSDName(bsdName: []const u8) !?[MAX_DEVICE_NAME:0]u8 {

    // Create a DiskArbitration session
    const session = c.DASessionCreate(c.kCFAllocatorDefault);
    if (session == null) return error.FailedToCreateDASession;
    defer c.CFRelease(session);

    const bsdNameCF = c.CFStringCreateWithBytes(
        c.kCFAllocatorDefault,
        bsdName.ptr,
        @intCast(bsdName.len),
        c.kCFStringEncodingUTF8,
        c.FALSE,
    );

    if (bsdNameCF == null) return error.FailedToCreateCFString;
    defer c.CFRelease(bsdNameCF);

    // Create disk reference
    const disk = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, session, bsdName.ptr);
    if (disk == null) return error.FailedToCreateDisk;
    defer c.CFRelease(disk);

    // Get disk description
    const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(disk));
    if (diskInfo == null) return error.FailedToGetDiskDescription;
    defer c.CFRelease(diskInfo);

    // _ = c.CFShow(diskInfo);

    const volumeNameStringRef: c.CFStringRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey));
    if (volumeNameStringRef == null or c.CFGetTypeID(volumeNameStringRef) != c.CFStringGetTypeID()) return null;

    var nameBuffer: [MAX_DEVICE_NAME:0]u8 = std.mem.zeroes([MAX_DEVICE_NAME:0]u8);

    const result: c.Boolean = c.CFStringGetCString(volumeNameStringRef, &nameBuffer, nameBuffer.len, c.kCFStringEncodingUTF8);
    if (result != c.TRUE) return null;

    return nameBuffer;
}
