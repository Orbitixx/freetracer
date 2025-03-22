const std = @import("std");

// pub fn parseLittleEndAsInt(comptime intType: type, endianBuffer: []const u8) !intType {
//
//
//     const parsedInt: intType = @bitCast(std.mem.readInt(i32, &tempBuffer, std.builtin.Endian.little));
//     return parsedInt;
// }
//
//

pub fn littleAsInt(endianBuffer: []const u8) i32 {
    std.mem.readInt(i32, endianBuffer, std.builtin.Endian.little);
}
