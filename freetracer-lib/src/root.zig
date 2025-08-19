const std = @import("std");
const testing = std.testing;

const isMacOS = (@import("builtin").os.tag == .macos);

const c_xpc = @cImport(@cInclude("xpc_helper.h"));

const constants = @import("./constants.zig");
const debug = @import("./util/debug.zig");
const types = @import("./types.zig");
const time = @import("./util/time.zig");
const string = @import("./util/string.zig");
const MacOSPermissions = @import("./macos/Permissions.zig");

pub const endian = @import("./util/endian.zig");
pub const iso9660 = @import("./util/iso9660.zig");

const Mach = @import("./macos/Mach.zig");
const IOKit = @import("./macos/IOKit.zig");

// Expose namespaces to be consumed by users
pub usingnamespace types;
pub usingnamespace constants;
pub usingnamespace time;
pub usingnamespace IOKit;

// MacOS-only export
pub usingnamespace if (isMacOS) Mach;
pub usingnamespace if (isMacOS) MacOSPermissions;

// Expose debug singleton to be consumed by users
pub const Debug = debug;
pub const String = string;

pub const xpc = c_xpc;
pub const ISOParser = @import("./ISOParser.zig");
