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

    pub fn deinit(self: @This()) void {
        self.pAllocator.*.free(self.bsdName);
    }
};

pub const USBDevice = struct {
    serviceId: c.io_service_t,
    deviceName: c.io_name_t,
    ioMediaVolumes: std.ArrayList(IOMediaVolume),

    pub fn deinit(self: @This()) void {
        for (self.ioMediaVolumes.items) |volume| {
            volume.deinit();
        }
        self.ioMediaVolumes.deinit();
    }
};

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
    const bsdNameKey = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOBSDNameKey, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(bsdNameKey);

    const leafKey = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOMediaLeafKey, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(leafKey);

    const sizeKey = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOMediaSizeKey, c.kCFStringEncodingUTF8, c.kCFAllocatorNull);
    defer _ = c.CFRelease(sizeKey);

    const bsdNameValueRef: c.CFStringRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, bsdNameKey, c.kCFAllocatorDefault, 0));
    if (bsdNameValueRef == null) return error.FailedToObtainBSDNameForVolume;
    defer _ = c.CFRelease(bsdNameValueRef);
    var bsdNameBuf: [128]u8 = undefined;

    const sizeValueRef: c.CFNumberRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, sizeKey, c.kCFAllocatorDefault, 0));
    if (sizeValueRef == null) return error.FailedToObtainIOMediaVolumeSize;
    defer _ = c.CFRelease(sizeValueRef);
    var mediaSizeInBytes: i64 = 0;

    _ = c.CFNumberGetValue(sizeValueRef, c.kCFNumberLongLongType, &mediaSizeInBytes);

    const leafValueRef: c.CFBooleanRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, leafKey, c.kCFAllocatorDefault, 0));
    if (leafValueRef == null) return error.FailedToObtainLeafKeyForVolume;
    defer _ = c.CFRelease(leafValueRef);
    const isLeaf: bool = (leafValueRef == c.kCFBooleanTrue);

    _ = c.CFStringGetCString(bsdNameValueRef, &bsdNameBuf, bsdNameBuf.len, c.kCFStringEncodingUTF8);

    // bsdNameBuf is a stack-allocated buffer, which is erased when function exits,
    // therefore the string must be saved on the heap and cleaned up later.
    const heapBsdName = try pAllocator.*.alloc(u8, bsdNameBuf.len);
    @memcpy(heapBsdName, &bsdNameBuf);

    return .{
        .pAllocator = pAllocator,
        .serviceId = service,
        .bsdName = heapBsdName,
        .size = mediaSizeInBytes,
        .isLeaf = isLeaf,
    };
}
