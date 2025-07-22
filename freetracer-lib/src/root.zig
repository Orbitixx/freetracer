const std = @import("std");
const testing = std.testing;

const c_xpc = @cImport(@cInclude("xpc_helper.h"));

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

// Expose debug singleton to be consumed by users
pub const Debug = debug;
pub const String = string;

pub const xpc = c_xpc;

// pub const xpc = struct {
//     pub fn start_xpc_server() void {
//         return c_xpc.start_xpc_server();
//     }
// };
