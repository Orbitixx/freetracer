const std = @import("std");

const freetracer_lib = @import("freetracer-lib");
const c = freetracer_lib.c;
const Debug = freetracer_lib.Debug;

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
    deviceNameBuf: [kDeviceNameBufferSize:0]u8 = undefined,
    bsdNameBuf: [kDeviceBsdNameBufferSize:0]u8 = undefined,
    size: i64 = undefined,
    volumes: std.ArrayList(IOMediaVolume) = undefined,

    pub fn deinit(self: USBStorageDevice) void {
        self.volumes.deinit();
        _ = c.IOObjectRelease(self.serviceId);
    }

    pub fn print(self: *USBStorageDevice) void {
        Debug.log(.INFO, "\n- /dev/{s}\t{s}\t({d})", .{
            self.getBsdNameSlice(),
            self.getNameSlice(),
            std.fmt.fmtIntSizeDec(@intCast(self.size)),
        });

        for (self.volumes.items) |volume| {
            Debug.log(.INFO, "\n\t- /dev/{s}\t({d})", .{
                self.getBsdNameSlice(),
                std.fmt.fmtIntSizeDec(@intCast(volume.size)),
            });
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
};
