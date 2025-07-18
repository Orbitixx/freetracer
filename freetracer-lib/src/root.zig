const std = @import("std");
const testing = std.testing;

const constants = @import("./constants.zig");
const debug = @import("./util/debug.zig");
const types = @import("./types.zig");
const mach = @import("./macos/mach.zig");
const time = @import("util/time.zig");
const string = @import("util/string.zig");

// Expose namespaces to be consumed by users
pub usingnamespace types;
pub usingnamespace constants;
pub usingnamespace time;

// MacOS-only export
pub usingnamespace if (@import("builtin").os.tag == .macos) mach;
// pub usingnamespace mach;

// Expose debug singleton to be consumed by users
pub const Debug = debug;

pub const String = string;
