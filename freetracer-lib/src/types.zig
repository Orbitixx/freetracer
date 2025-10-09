// Defines primitive cross-platform and macOS specific types shared between the
// GUI client and privileged helper, including C imports, device/image enums,
// and helper structs used by Disk Arbitration and raw write logic.
// Functions here provide safe views over fixed-size buffers so the rest of the
// codebase can work with Zig slices without duplicating sentinel management.
// ------------------------------------------------------------------------------
const std = @import("std");
const Debug = @import("util/debug.zig");
const Character = @import("constants.zig").Character;

pub const isMac = @import("builtin").os.tag == .macos;
pub const isMacOS = @import("builtin").os.tag == .macos;
pub const isLinux = @import("builtin").os.tag == .linux;

pub const c = if (isMac) @cImport({
    @cInclude("DiskArbitration/DiskArbitration.h");
    @cInclude("CoreFoundation/CFBase.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    // -- For CFLaunch serivces (opening Settings app)
    @cInclude("CoreServices/CoreServices.h");
    // -- IOKit constants, methods
    @cInclude("IOKit/usb/USB.h");
    @cInclude("IOKit/usb/IOUSBLib.h");
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("IOKit/storage/IOMedia.h");
    @cInclude("IOKit/storage/IOBlockStorageDevice.h");
    @cInclude("IOKit/IOCFPlugIn.h");
    @cInclude("IOKit/IOBSD.h");
    // --- Privileged Helper Tool: SMJobBless
    @cInclude("ServiceManagement/ServiceManagement.h");
    // --- DADiskRef Authorization
    @cInclude("Security/Authorization.h");
    @cInclude("sys/disk.h");
    @cInclude("sys/ioctl.h");
    // --- XPC Connection/Message validation
    @cInclude("Security/CSCommon.h");
    @cInclude("Security/SecBase.h");
    @cInclude("Security/SecCode.h");
    @cInclude("Security/Security.h");
    // --- For getpwuid()
    @cInclude("pwd.h");
    // @cInclude("bootstrap.h");
    // @cInclude("mach/mach.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
}) else if (isLinux) @cImport({
    // @cInclude("blkid/blkid.h");
});

pub const WriteRequestData = struct {
    devicePath: [:0]const u8,
    isoPath: [:0]const u8,
};

pub const MAX_BSD_NAME: usize = 64;
pub const MAX_DEVICE_NAME: usize = std.fs.max_name_bytes;

pub const DeviceType = enum(u64) {
    USB,
    SD,
    Other,
};

pub const ImageType = enum(u64) {
    ISO,
    IMG,
    Other,
};

pub const Image = struct {
    path: ?[:0]u8 = null,
    type: ImageType = undefined,
};

pub const StorageDevice = struct {
    serviceId: c.io_service_t,
    deviceName: [std.fs.max_name_bytes:0]u8,
    bsdName: [MAX_BSD_NAME:0]u8,
    type: DeviceType,
    size: i64,

    /// Returns the user-presentable device name as a sentinel-terminated slice.
    pub fn getNameSlice(self: *const StorageDevice) [:0]const u8 {
        std.debug.assert((self.deviceName[0] != Character.NULL) and
            (self.deviceName[0] > Character.FIRST_PRINTABLE_CHARACTER) and
            (self.deviceName[0] < Character.LAST_PRINTABLE_CHARACTER));

        return std.mem.sliceTo(@constCast(self).deviceName[0..@constCast(self).deviceName.len], Character.NULL);
    }

    /// Returns the BSD identifier (e.g. "disk2") as a sentinel-terminated slice.
    pub fn getBsdNameSlice(self: *const StorageDevice) [:0]const u8 {
        std.debug.assert((self.bsdName[0] != Character.NULL) and
            (self.bsdName[0] > Character.FIRST_PRINTABLE_CHARACTER) and
            (self.bsdName[0] < Character.LAST_PRINTABLE_CHARACTER));

        return std.mem.sliceTo(@constCast(self).bsdName[0..@constCast(self).bsdName.len], Character.NULL);
    }
    /// Writes a debug log entry describing the device (type, BSD name, size).
    pub fn print(self: *const StorageDevice) void {
        Debug.log(.INFO, "Storage Device: {s} ({s}) - Size: {d} bytes", .{ self.deviceName, self.bsdName, self.size });
    }
};
