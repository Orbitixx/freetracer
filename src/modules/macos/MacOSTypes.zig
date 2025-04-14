const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

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
    allocator: std.mem.Allocator,
    serviceId: c.io_service_t,
    bsdName: []const u8,
    size: i64,
    isLeaf: bool,
    isWhole: bool,
    isRemovable: bool,
    isOpen: bool,
    isWritable: bool,

    pub fn deinit(self: IOMediaVolume) void {
        self.allocator.free(self.bsdName);
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
    allocator: std.mem.Allocator,
    serviceId: c.io_service_t = undefined,
    deviceName: []u8 = undefined,
    bsdName: []u8 = undefined,
    size: i64 = undefined,
    volumes: std.ArrayList(IOMediaVolume) = undefined,

    pub fn deinit(self: USBStorageDevice) void {
        self.allocator.free(self.deviceName);
        self.allocator.free(self.bsdName);

        for (self.volumes.items) |volume| {
            self.allocator.free(volume.bsdName);
        }

        self.volumes.deinit();
    }

    pub fn print(self: USBStorageDevice) void {
        debug.printf("\n- /dev/{s}\t{s}\t({d})", .{ self.bsdName, self.deviceName, std.fmt.fmtIntSizeDec(@intCast(self.size)) });

        for (self.volumes.items) |volume| {
            debug.printf("\n\t- /dev/{s}\t({d})", .{ volume.bsdName, std.fmt.fmtIntSizeDec(@intCast(volume.size)) });
        }
    }
};
