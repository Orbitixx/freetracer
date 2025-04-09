const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const isMac: bool = @import("builtin").os.tag == .macos;
const isLinux: bool = @import("builtin").os.tag == .linux;

const c = if (isMac) @cImport({
    @cInclude("IOKit/storage/IOMedia.h");
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("IOKit/usb/USB.h");
    @cInclude("IOKit/usb/IOUSBLib.h");
    @cInclude("IOKit/IOCFPlugIn.h");
    @cInclude("IOKit/IOBSD.h");
}) else if (isLinux) @cImport({});

pub const IOMediaVolume = struct {
    pAllocator: *const std.mem.Allocator,
    serviceId: c.io_service_t,
    bsdName: []const u8,
    size: i64,
    isLeaf: bool,
    isWhole: bool,
    isRemovable: bool,
    isOpen: bool,
    isWritable: bool,

    pub fn deinit(self: @This()) void {
        self.pAllocator.*.free(self.bsdName);
    }
};

pub const USBDevice = struct {
    serviceId: c.io_service_t,
    deviceName: c.io_name_t,
    ioMediaVolumes: std.ArrayList(IOMediaVolume),

    pub fn deinit(self: USBDevice) void {
        for (self.ioMediaVolumes.items) |volume| {
            volume.deinit();
        }
        self.ioMediaVolumes.deinit();
    }
};

pub const USBStorageDevice = struct {
    pAllocator: *const std.mem.Allocator,
    serviceId: c.io_service_t = undefined,
    deviceName: []u8 = undefined,
    bsdName: []u8 = undefined,
    size: i64 = undefined,
    volumes: std.ArrayList(IOMediaVolume) = undefined,

    pub fn deinit(self: USBStorageDevice) void {
        self.pAllocator.*.free(self.deviceName);
        self.pAllocator.*.free(self.bsdName);
        self.volumes.deinit();
    }

    pub fn print(self: USBStorageDevice) void {
        debug.printf("\n- /dev/{s}\t{s}\t({d})", .{ self.bsdName, self.deviceName, std.fmt.fmtIntSizeDec(@intCast(self.size)) });

        for (self.volumes.items) |volume| {
            debug.printf("\n\t- /dev/{s}\t({d})", .{ volume.bsdName, std.fmt.fmtIntSizeDec(@intCast(volume.size)) });
        }
    }

    pub fn unmountAllVolumes(self: USBStorageDevice) !void {
        //
        // TODO: Check for EFI partition -- do not attempt to unmount it
        //
        const daSession = c.DASessionCreate(c.kCFAllocatorDefault);

        if (daSession == null) {
            debug.print("ERROR: Failed to create DASession\n");
            return error.FailedToCreateDiskArbitrationSession;
        }
        defer _ = c.CFRelease(daSession);

        const currentLoop = c.CFRunLoopGetCurrent();
        c.DASessionScheduleWithRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

        // Ensure unscheduling happens before session is released
        defer c.DASessionUnscheduleFromRunLoop(daSession, currentLoop, c.kCFRunLoopDefaultMode);

        // const bsdName = "disk4s1";
        //
        // const daDiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, bsdName);
        //
        // if (daDiskRef == null) debug.print("\nERROR: CANNOT CREATE DISK REFERENCE.");
        //
        // c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionForce, unmountDiskCallback, null);
        // c.CFRunLoopRun();

        var queuedUnmounts: u8 = 0;

        for (self.volumes.items) |volume| {
            const daDiskRef = c.DADiskCreateFromBSDName(c.kCFAllocatorDefault, daSession, volume.bsdName.ptr);

            if (daDiskRef == null) {
                debug.printf("\nWARNING: Could not create DADiskRef for '{s}', skipping.\n", .{volume.bsdName});
                continue;
            }
            defer _ = c.CFRelease(daDiskRef);

            const diskInfo: c.CFDictionaryRef = @ptrCast(c.DADiskCopyDescription(daDiskRef));
            defer _ = c.CFRelease(diskInfo);

            // Do not release efiKey, release causes segmentation fault
            const efiKey: c.CFStringRef = @ptrCast(c.CFDictionaryGetValue(diskInfo, c.kDADiskDescriptionVolumeNameKey));

            _ = c.CFShow(diskInfo);

            var efiKeyBuf: [128]u8 = undefined;
            _ = c.CFStringGetCString(efiKey, &efiKeyBuf, efiKeyBuf.len, c.kCFStringEncodingUTF8);

            if (efiKey != null) debug.printf("\nDisk EFI Key: {s}", .{efiKeyBuf});

            debug.printf("\nInitiating unmount call for disk: {s}", .{volume.bsdName});

            queuedUnmounts += 1;
            c.DADiskUnmount(daDiskRef, c.kDADiskUnmountOptionForce, unmountDiskCallback, &queuedUnmounts);
        }

        if (queuedUnmounts > 0) {
            c.CFRunLoopRun();
        } else {
            debug.print("\nERROR: No valid unmount calls could be initiated.");
        }
    }
};

fn unmountDiskCallback(disk: c.DADiskRef, dissenter: c.DADissenterRef, context: ?*anyopaque) callconv(.C) void {
    if (context == null) {
        debug.print("\nERROR: Unmount callback returned NULL context.");
        return;
    }

    const counter_ptr: *u8 = @ptrCast(context);
    // _ = context;
    const bsdName = if (c.DADiskGetBSDName(disk)) |name| toSlice(name) else "Unknown Disk";

    if (dissenter != null) {
        debug.print("\nWARNING: Disk Arbitration Dissenter returned a non-empty status.");

        const status = c.DADissenterGetStatus(dissenter);
        const statusStringRef = c.DADissenterGetStatusString(dissenter);
        var statusString: [256]u8 = undefined;

        if (statusStringRef != null) {
            _ = c.CFStringGetCString(statusStringRef, &statusString, statusString.len, c.kCFStringEncodingUTF8);
        }

        debug.printf("\nERROR: Failed to unmount {s}. Dissenter status code: {any}, status message: {s}", .{ bsdName, status, statusString });
    } else {
        debug.printf("\nSuccessfully unmounted disk: {s}", .{bsdName});
        counter_ptr.* -= 1;
    }

    if (counter_ptr.* == 0) {
        debug.print("\nSuccessfully unmounted all volumes for device.");
        const currentLoop = c.CFRunLoopGetCurrent();
        c.CFRunLoopStop(currentLoop);
    }
}

pub fn getIOMediaVolumesForDevice(device: c.io_service_t, pAllocator: *const std.mem.Allocator, pVolumesList: *std.ArrayList(IOMediaVolume)) !void {
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
            const ioMediaVolume = try getIOMediaVolumeDescription(childService, pAllocator);

            pVolumesList.*.append(ioMediaVolume) catch |err| {
                debug.printf("\nERROR (IOKit.getIOMediaVolumesForDevice): unable to append child service to volumes list. Error message: {any}", .{err});
            };
        }

        try getIOMediaVolumesForDevice(childService, pAllocator, pVolumesList);
    }

    defer _ = c.IOObjectRelease(childIterator);
}

pub fn getIOMediaVolumeDescription(service: c.io_service_t, pAllocator: *const std.mem.Allocator) !IOMediaVolume {

    //--- @prop: BSDName (String) --------------------------------------------------------
    //------------------------------------------------------------------------------------
    const bsdNameKey: c.CFStringRef = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOBSDNameKey, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(bsdNameKey);

    // const str = try toCString(pAllocator, c.kIOBSDNameKey);
    // defer pAllocator.*.free(str);
    //
    // const bsdNameKey: c.CFStringRef = @ptrCast(str);

    const bsdNameValueRef: c.CFStringRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, bsdNameKey, c.kCFAllocatorDefault, 0));
    if (bsdNameValueRef == null) return error.FailedToObtainBSDNameForVolume;
    defer _ = c.CFRelease(bsdNameValueRef);
    var bsdNameBuf: [128]u8 = undefined;

    _ = c.CFStringGetCString(bsdNameValueRef, &bsdNameBuf, bsdNameBuf.len, c.kCFStringEncodingUTF8);

    // bsdNameBuf is a stack-allocated buffer, which is erased when function exits,
    // therefore the string must be saved on the heap and cleaned up later.
    const heapBsdName = try pAllocator.*.alloc(u8, bsdNameBuf.len);
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
        .pAllocator = pAllocator,
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

pub fn toCString(pAllocator: *const std.mem.Allocator, string: []const u8) ![]u8 {
    if (string.len == 0) return error.OriginalStringMustBeNonZeroLength;

    var cString: []u8 = pAllocator.*.alloc(u8, string.len + 1) catch |err| {
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
