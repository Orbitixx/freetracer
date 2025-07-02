const std = @import("std");
const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const Linux = @import("../../modules/linux/LinuxTypes.zig");

pub const isMac = @import("builtin").os.tag == .macos;
pub const isLinux = @import("builtin").os.tag == .linux;

pub const c = if (isMac) @cImport({
    @cInclude("IOKit/storage/IOMedia.h");
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("DiskArbitration/DiskArbitration.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("IOKit/usb/USB.h");
    @cInclude("IOKit/usb/IOUSBLib.h");
    @cInclude("IOKit/IOCFPlugIn.h");
    @cInclude("IOKit/IOBSD.h");
    @cInclude("ServiceManagement/ServiceManagement.h");
    @cInclude("Security/Authorization.h");
}) else if (isLinux) @cImport({
    // @cInclude("blkid/blkid.h");
});

// comptime type selector
pub const USBStorageDevice = if (isMac) MacOS.USBStorageDevice else if (isLinux) Linux.USBStorageDevice else {
    std.debug.panic("\nCRITICAL ERROR: unable to determine system type (MacOS or Linux) at runtime.", .{});
    unreachable;
};
