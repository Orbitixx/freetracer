const std = @import("std");
const types = @import("../types.zig");
const Debug = @import("../util/debug.zig");
const constants = @import("../constants.zig");

const c = types.c;
const StorageDevice = types.StorageDevice;
const MAX_BSD_NAME = types.MAX_BSD_NAME;
const MAX_DEVICE_NAME = types.MAX_DEVICE_NAME;

const Character = constants.Character;
const DefaultNameString = constants.k.DefaultDeviceName;

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
    @memcpy(defaultDeviceName[0..DefaultNameString.len], DefaultNameString);

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
