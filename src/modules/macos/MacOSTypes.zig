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
    pub const kVolumeBsdNameBufferSize: usize = 128;

    allocator: std.mem.Allocator,
    serviceId: c.io_service_t,
    bsdNameBuf: [kVolumeBsdNameBufferSize:0]u8 = undefined,
    size: i64,
    isLeaf: bool,
    isWhole: bool,
    isRemovable: bool,
    isOpen: bool,
    isWritable: bool,
};

pub const USBDevice = struct {
    serviceId: c.io_service_t,
    deviceName: c.io_name_t,
    ioMediaVolumes: std.ArrayList(IOMediaVolume),

    pub fn deinit(self: USBDevice) void {
        self.ioMediaVolumes.deinit();
        _ = c.IOObjectRelease(self.serviceId);
    }
};

pub const USBStorageDevice = struct {
    pub const kDeviceNameBufferSize: usize = 128;
    pub const kDeviceBsdNameBufferSize: usize = 128;

    allocator: std.mem.Allocator,
    serviceId: c.io_service_t = undefined,
    connection: ?c.io_connect_t = null,
    deviceNameBuf: [kDeviceNameBufferSize:0]u8 = undefined,
    bsdNameBuf: [kDeviceBsdNameBufferSize:0]u8 = undefined,
    size: i64 = undefined,
    volumes: std.ArrayList(IOMediaVolume) = undefined,

    pub fn deinit(self: USBStorageDevice) void {
        self.volumes.deinit();
        _ = c.IOObjectRelease(self.serviceId);
    }

    pub fn print(self: *USBStorageDevice) void {
        debug.printf("\n- /dev/{s}\t{s}\t({d})", .{ self.getBsdNameSlice(), self.getNameSlice(), std.fmt.fmtIntSizeDec(@intCast(self.size)) });

        for (self.volumes.items) |volume| {
            debug.printf("\n\t- /dev/{s}\t({d})", .{ self.getBsdNameSlice(), std.fmt.fmtIntSizeDec(@intCast(volume.size)) });
        }
    }

    pub fn getNameSlice(self: *const USBStorageDevice) [:0]const u8 {
        std.debug.assert(self.deviceNameBuf[0] != 0x00 or self.deviceNameBuf[0] != 0x170);
        return std.mem.sliceTo(@constCast(self).deviceNameBuf[0..@constCast(self).deviceNameBuf.len], 0x00);
    }

    pub fn getBsdNameSlice(self: *const USBStorageDevice) [:0]const u8 {
        std.debug.assert(self.bsdNameBuf[0] != 0x00 or self.bsdNameBuf[0] != 0x170);
        return std.mem.sliceTo(@constCast(self).bsdNameBuf[0..@constCast(self).bsdNameBuf.len], 0x00);
    }

    pub fn open(self: *USBStorageDevice) !void {
        const deviceBsdName = self.getBsdNameSlice();

        // Convert BSD name to CFString
        const bsdNameRef = c.CFStringCreateWithCString(c.kCFAllocatorDefault, deviceBsdName.ptr, c.kCFStringEncodingUTF8);

        if (bsdNameRef) |ref| {
            defer c.CFRelease(ref);
        } else return error.FailedToObtainBSDNameRef;

        // Open connection to the service
        const kr = c.IOServiceOpen(self.serviceId, c.mach_task_self(), 0, &self.connection.?);

        if (kr != c.KERN_SUCCESS) {
            return error.IOServiceOpenFailed;
        }
    }

    pub fn writeBlocks(self: *const USBStorageDevice, writeBuffer: []const u8, start_block: u64, block_count: u64) !usize {
        const inputStruct = struct {
            offset: u64,
            length: u64,
        }{
            .offset = start_block,
            .length = block_count,
        };

        var outputSize: usize = 0;

        const kr = c.IOConnectCallStructMethod(self.connection.?, 1, // Method selector for write
            &inputStruct, @sizeOf(@TypeOf(inputStruct)), @ptrCast(@constCast(writeBuffer.ptr)), &outputSize);

        if (kr != c.KERN_SUCCESS) {
            return error.WriteFailed;
        }

        return writeBuffer.len;
    }
};
