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
    // --- XPC Connection/Message validation
    @cInclude("Security/CSCommon.h");
    @cInclude("Security/SecBase.h");
    @cInclude("Security/SecCode.h");
    @cInclude("Security/Security.h");
    // --- For getpwuid()
    @cInclude("pwd.h");
    // @cInclude("bootstrap.h");
    // @cInclude("mach/mach.h");
}) else if (isLinux) @cImport({
    // @cInclude("blkid/blkid.h");
});

pub const WriteRequestData = struct {
    devicePath: [:0]const u8,
    isoPath: [:0]const u8,
};

pub const MAX_BSD_NAME: usize = 64;
pub const MAX_DEVICE_NAME: usize = std.fs.max_name_bytes;

pub const StorageDevice = struct {
    serviceId: c.io_service_t,
    deviceName: [std.fs.max_name_bytes:0]u8,
    bsdName: [MAX_BSD_NAME:0]u8,
    size: i64,

    pub fn getNameSlice(self: *const StorageDevice) [:0]const u8 {
        std.debug.assert((self.deviceName[0] != Character.NULL) and
            (self.deviceName[0] > Character.FIRST_PRINTABLE_CHARACTER) and
            (self.deviceName[0] < Character.LAST_PRINTABLE_CHARACTER));

        return std.mem.sliceTo(@constCast(self).deviceName[0..@constCast(self).deviceName.len], Character.NULL);
    }

    pub fn getBsdNameSlice(self: *const StorageDevice) [:0]const u8 {
        std.debug.assert((self.bsdName[0] != Character.NULL) and
            (self.bsdName[0] > Character.FIRST_PRINTABLE_CHARACTER) and
            (self.bsdName[0] < Character.LAST_PRINTABLE_CHARACTER));
        return std.mem.sliceTo(@constCast(self).bsdName[0..@constCast(self).bsdName.len], Character.NULL);
    }

    pub fn print(self: *const StorageDevice) void {
        Debug.log(.INFO, "Storage Device: {s} ({s}) - Size: {d} bytes", .{ self.deviceName, self.bsdName, self.size });
    }
};
