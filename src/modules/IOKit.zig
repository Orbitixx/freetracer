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
    serviceId: c.io_service_t,
    bsdName: []const u8,
    isLeaf: bool,
};

pub const USBDevice = struct {
    serviceId: c.io_service_t,
    deviceName: c.io_name_t,
    ioMediaVolumes: std.ArrayList(IOMediaVolume),

    pub fn deinit(self: @This()) void {
        self.ioMediaVolumes.deinit();
    }
};

pub fn getIOMediaVolumesForDevice(device: c.io_service_t, pVolumesList: *std.ArrayList(IOMediaVolume)) !void {
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

        if (!isIOMedia) {
            try getIOMediaVolumesForDevice(childService, pVolumesList);
        } else {
            const ioMediaVolume = try getIOMediaVolumeDescription(childService);
            pVolumesList.*.append(ioMediaVolume) catch |err| {
                debug.printf("\nERROR (IOKit.getIOMediaVolumesForDevice): unable to append child service to volumes list. Error message: {any}", .{err});
            };
        }
    }

    defer _ = c.IOObjectRelease(childIterator);
}

pub fn getIOMediaVolumeDescription(service: c.io_service_t) !IOMediaVolume {
    const bsdNameKey = c.CFStringCreateWithCString(c.kCFAllocatorDefault, c.kIOBSDNameKey, c.kCFStringEncodingUTF8);
    const leafKey = c.CFStringCreateWithCStringNoCopy(c.kCFAllocatorDefault, c.kIOMediaLeafKey, c.kCFStringEncodingASCII, c.kCFAllocatorNull);

    const bsdNameKeyRef: c.CFStringRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, bsdNameKey, c.kCFAllocatorDefault, 0));
    if (bsdNameKeyRef == null) return error.UnableToLocateBSDNameForVolume;
    defer _ = c.CFRelease(bsdNameKeyRef);
    var bsdNameBuf: [128]u8 = undefined;

    const leafKeyRef: c.CFBooleanRef = @ptrCast(c.IORegistryEntryCreateCFProperty(service, leafKey, c.kCFAllocatorDefault, 0));
    if (leafKeyRef == null) return error.UnableToLocateLeafKeyForVolume;
    defer _ = c.CFRelease(leafKeyRef);
    const isLeaf: bool = leafKeyRef == c.kCFBooleanTrue;

    _ = c.CFStringGetCString(bsdNameKeyRef, &bsdNameBuf, bsdNameBuf.len, c.kCFStringEncodingUTF8);

    return .{
        .serviceId = service,
        .bsdName = &bsdNameBuf,
        .isLeaf = isLeaf,
    };
}
