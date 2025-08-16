const std = @import("std");
const testing = std.testing;

const c_xpc = @cImport(@cInclude("xpc_helper.h"));

const constants = @import("./constants.zig");
const debug = @import("./util/debug.zig");
const types = @import("./types.zig");
const time = @import("./util/time.zig");
const string = @import("./util/string.zig");
const Mach = @import("./macos/Mach.zig");
const IOKit = @import("./macos/IOKit.zig");

// Expose namespaces to be consumed by users
pub usingnamespace types;
pub usingnamespace constants;
pub usingnamespace time;
pub usingnamespace IOKit;

// MacOS-only export
pub usingnamespace if (@import("builtin").os.tag == .macos) Mach;

// Expose debug singleton to be consumed by users
pub const Debug = debug;
pub const String = string;

pub const xpc = c_xpc;
pub const ISOParser = @import("./ISOParser.zig");
