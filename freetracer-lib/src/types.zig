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
    @cInclude("bootstrap.h");
    @cInclude("mach/mach.h");
}) else if (isLinux) @cImport({
    // @cInclude("blkid/blkid.h");
});

pub const WriteRequestData = struct {
    devicePath: [:0]const u8,
    isoPath: [:0]const u8,
};
