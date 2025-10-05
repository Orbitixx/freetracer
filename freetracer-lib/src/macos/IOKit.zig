const std = @import("std");
const types = @import("../types.zig");
const Debug = @import("../util/debug.zig");
const constants = @import("../constants.zig");

const c = types.c;
const StorageDevice = types.StorageDevice;
const DeviceType = types.DeviceType;
const MAX_BSD_NAME = types.MAX_BSD_NAME;
const MAX_DEVICE_NAME = types.MAX_DEVICE_NAME;

const Character = constants.Character;
const DefaultNameString = constants.k.DefaultDeviceName;

const PhysicalDeviceCheckResult = struct {
    isPhysical: bool = false,
    deviceType: DeviceType = .Other,
};

pub fn getStorageDevices(allocator: std.mem.Allocator) !std.ArrayList(StorageDevice) {
    Debug.log(.DEBUG, "Querying storage devices from IORegistry...", .{});

    var storageDevices = std.ArrayList(StorageDevice).empty;

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
        const result = checkPhysicalDevice(currentService);

        if (!result.isPhysical) {
            _ = c.IOObjectRelease(currentService);
            currentService = c.IOIteratorNext(serviceIterator);
            continue;
        }

        const device = getStorageDeviceFromService(currentService, result.deviceType) catch |err| {
            _ = c.IOObjectRelease(currentService);
            return err;
        };

        try storageDevices.append(allocator, device);
        currentService = c.IOIteratorNext(serviceIterator);
    }

    return storageDevices;
}

fn getStorageDeviceFromService(service: c.io_service_t, deviceType: DeviceType) !StorageDevice {
    Debug.log(.DEBUG, "Discovered a device. Querying device details...", .{});

    const bsdName = try getStringFromIOService(service, c.kIOBSDNameKey, MAX_BSD_NAME);
    const bsdNameSlice = std.mem.sliceTo(&bsdName, Character.NULL);
    if (bsdNameSlice.len < 3) return error.BSDNameTooShort;

    const size: i64 = try getNumberFromIOService(service, c.kIOMediaSizeKey, c.kCFNumberSInt64Type, i64);

    var defaultDeviceName: [MAX_DEVICE_NAME:0]u8 = std.mem.zeroes([MAX_DEVICE_NAME:0]u8);
    @memcpy(defaultDeviceName[0..DefaultNameString.len], DefaultNameString);

    const deviceName: [MAX_DEVICE_NAME:0]u8 = try getVolumeNameFromBSDName(bsdNameSlice) orelse defaultDeviceName;

    Debug.log(.DEBUG, "\tPreparing to query device type...", .{});
    // const deviceType: DeviceType = getDeviceType(service);

    return StorageDevice{
        .serviceId = service,
        .bsdName = bsdName,
        .deviceName = deviceName,
        .size = size,
        .type = deviceType,
    };
}

/// Checks whether service is a physical device or a virtual disk (e.g. a mounted dmg volume).
/// This check is accomplished by querying the kIOPropertyProtocolCharacteristicsKey property,
/// which only physical devices should posses.
fn checkPhysicalDevice(service: c.io_service_t) PhysicalDeviceCheckResult {
    Debug.log(.DEBUG, "Attempting to check if device is a physical disk...", .{});

    var result: PhysicalDeviceCheckResult = .{};
    defer Debug.log(.INFO, "\t\t\tCompleted physical disk check, physical disk: {any}", .{result});

    const protocolCharacteristicsKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyProtocolCharacteristicsKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(protocolCharacteristicsKey);

    const physicalInterconnectKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyPhysicalInterconnectTypeKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectKey);

    const physicalInterconnectLocationKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyPhysicalInterconnectLocationKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectLocationKey);

    const physicalInterconnectUSBKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyPhysicalInterconnectTypeUSB, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectLocationKey);

    const physicalInterconnectSDKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyPhysicalInterconnectTypeSecureDigital, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectLocationKey);

    const physicalInterconnectExternalKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyExternalKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectLocationKey);

    const physicalInterconnectInternalKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOPropertyInternalKey, c.kCFStringEncodingUTF8);
    defer _ = c.CFRelease(physicalInterconnectLocationKey);

    var parentService: c.io_object_t = service;
    var currentService = service;
    var kernResult: c.kern_return_t = undefined;

    Debug.log(.DEBUG, "\t\tRecursing to query parent devices...", .{});

    // Max recurse depth of MAX_IOKIT_DEVICE_RECURSE_NUM levels (e.g.: 10)
    for (0..constants.MAX_IOKIT_DEVICE_RECURSE_NUM) |i| {
        Debug.log(.DEBUG, "\t\t\tLevel {d}: obtaining a parent entry...", .{i});
        kernResult = c.IORegistryEntryGetParentEntry(currentService, c.kIOServicePlane, &parentService);

        // If successfully obtained parent, no longer need child service handle
        if (currentService != service) _ = c.IOObjectRelease(currentService);

        if (kernResult != c.KERN_SUCCESS or parentService == 0) {
            Debug.log(.DEBUG, "\t\t\tReached the end of recurse length or failed to obtain parent...", .{});
            break; // No more parents, stop searching.
        }

        currentService = parentService;

        Debug.log(.DEBUG, "\t\t\tCreating a CFProperty from IORegistry entry...", .{});

        const characteristicsDict = c.IORegistryEntryCreateCFProperty(currentService, protocolCharacteristicsKey, c.kCFAllocatorDefault, 0);

        if (characteristicsDict == null) continue else {
            defer _ = c.CFRelease(characteristicsDict);

            if (currentService != service) {
                defer _ = c.IOObjectRelease(currentService);
            }

            if (c.CFGetTypeID(characteristicsDict) != c.CFDictionaryGetTypeID()) {
                Debug.log(
                    .WARNING,
                    "\t\t\tStrangely, the Protocol Characteristics property is not NULL but it is also not a CFDictionary... Returning false as NOT PHYSICAL DEVICE.",
                    .{},
                );

                result = .{ .isPhysical = false };
                return result;
            }

            const interconnectValue = c.CFDictionaryGetValue(@ptrCast(characteristicsDict), physicalInterconnectKey);
            const interconnectLocationValue = c.CFDictionaryGetValue(@ptrCast(characteristicsDict), physicalInterconnectLocationKey);

            if (interconnectValue == null or interconnectLocationValue == null) {
                Debug.log(.WARNING, "\t\t\tPhysical Interconnect or Interconnect Location is null; returning false.", .{});
                result = .{ .isPhysical = false };
                return result;
            }

            const isUSB = c.CFStringCompare(@ptrCast(interconnectValue), physicalInterconnectUSBKey, 0) == c.kCFCompareEqualTo;
            const isSD = c.CFStringCompare(@ptrCast(interconnectValue), physicalInterconnectSDKey, 0) == c.kCFCompareEqualTo;
            const isExternal = c.CFStringCompare(@ptrCast(interconnectLocationValue), physicalInterconnectExternalKey, 0) == c.kCFCompareEqualTo;
            const isInternal = c.CFStringCompare(@ptrCast(interconnectLocationValue), physicalInterconnectInternalKey, 0) == c.kCFCompareEqualTo;

            Debug.log(.DEBUG, "\t\t\tisUSB: {any}, isSD: {any}, isExternal: {any}, isInternal: {any}", .{ isUSB, isSD, isExternal, isInternal });

            if ((isUSB and isExternal) or (isSD and isInternal)) {
                result = .{ .isPhysical = true, .deviceType = if (isUSB) .USB else if (isSD) .SD else .Other };
                return result;
            }
        }
    }

    if (currentService != service) _ = c.IOObjectRelease(currentService);
    result = .{ .isPhysical = false };
    return result;
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
