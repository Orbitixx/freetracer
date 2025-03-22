const std = @import("std");
const eltorito = @import("eltorito.zig");
const debug = @import("../util/debug.zig");

pub const PrimaryVolumeDescriptor = struct {};

pub const BootRecord = struct {
    typeCode: u8,
    identifier: [5]u8,
    version: u8,
    bootSystemIdentifier: [32]u8,
    bootIdentifier: [32]u8,

    // El Torito Spec

    /// Points to the BootCatalog, little-endian 32 bit int
    catalogLba: [4]u8,
    unused: [1973]u8,

    pub fn print(self: @This()) void {
        debug.print("\n\n-------------------------- BootRecord ---------------------------");
        debug.printf("\n\tType Code:\t\t\t{d}", .{self.typeCode});
        debug.printf("\n\tIdentifier:\t\t\t{s}", .{self.identifier});
        debug.printf("\n\tVersion:\t\t\t{d}", .{self.version});
        debug.printf("\n\tBoot System Identifier:\t\t{s}", .{self.bootSystemIdentifier});
        debug.printf("\n\tBoot Identifier:\t\t{s}", .{self.bootIdentifier});
        debug.printf("\n\tCatalog LBA:\t\t\t{d}\n", .{std.mem.readInt(i32, &self.catalogLba, std.builtin.Endian.little)});
    }
};

pub const BootCatalog = struct {
    validationEntry: eltorito.ValidationEntry, // 32b
    initialDefaultEntry: eltorito.InitialDefaultEntry, // 32b

    // Optional sector head and entries
    // https://dev.lovelyhq.com/libburnia/libisofs/raw/branch/master/doc/boot_sectors.txt
    optional: [1984]u8,
};
