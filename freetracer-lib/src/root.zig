const std = @import("std");
const testing = std.testing;

const isMacOS = (@import("builtin").os.tag == .macos);

const c_xpc = @cImport(@cInclude("xpc_helper.h"));

pub const constants = @import("./constants.zig");
const debug = @import("./util/debug.zig");
pub const types = @import("./types.zig");
pub const time = @import("./util/time.zig");
pub const string = @import("./util/string.zig");
pub const MacOSPermissions = @import("./macos/Permissions.zig");
pub const DiskArbitration = @import("./macos/DiskArbitration.zig");
pub const device = @import("./util/device.zig");

pub const fs = @import("./macos/FileSystem.zig");
pub const endian = @import("./util/endian.zig");
pub const iso9660 = @import("./util/iso9660.zig");

pub const Mach = @import("./macos/Mach.zig");
pub const IOKit = @import("./macos/IOKit.zig");

pub const c = types.c;
pub const StorageDevice = types.StorageDevice;

// Expose debug singleton to be consumed by users
pub const Debug = debug;
pub const String = string;

pub const xpc = c_xpc;
pub const ISOParser = @import("./ISOParser.zig");
