const std = @import("std");
const endian = @import("../util/endian.zig");
const debug = @import("../util/debug.zig");

pub const ValidationEntry = struct {
    headerId: u8,
    platformId: u8,
    reserved1: u8,
    reserved2: u8,
    manufacturerDev: [24]u8,
    checksum: [2]u8,
    signature1: u8,
    signature2: u8,

    pub fn print(self: @This()) void {
        debug.print("\n\n---------------------------- El Torito Validation Entry -----------------------------");
        debug.printf("\n\tHeader ID:\t\t\t0x{x}", .{self.headerId});
        debug.printf("\n\tPlatform ID:\t\t\t0x{x}", .{self.platformId});
        debug.printf("\n\tReserved1:\t\t\t0x{x}", .{self.reserved1});
        debug.printf("\n\tReserved2:\t\t\t0x{x}", .{self.reserved2});
        debug.printf("\n\tManufacturer/Developer:\t{s}", .{self.manufacturerDev});
        debug.printf("\n\tChecksum:\t\t\t{any}", .{self.checksum});
        debug.printf("\n\tSignature 1:\t\t\t0x{x}", .{self.signature1});
        debug.printf("\n\tSignature 2:\t\t\t0x{x}", .{self.signature2});
        debug.print("\n-------------------------------------------------------------------------------\n");
    }
};

pub const InitialDefaultEntry = struct {
    bootIndicator: u8,
    bootMedia: u8,
    loadSegment: [2]u8,
    systemType: u8,
    unused1: u8,
    ///int16_LSB
    sectorCount: [2]u8,
    /// int32_LSB
    loadRba: [4]u8,
    unused2: [20]u8,

    pub fn print(self: @This()) void {
        debug.print("\n\n---------------------------- El Torito Initial/Default Entry ----------------------");
        debug.printf("\n\tBoot Indicator:\t\t0x{x}", .{self.bootIndicator});
        debug.printf("\n\tBoot Media:\t\t{b:0>8}", .{self.bootMedia});
        debug.printf("\n\tLoad Segment:\t\t{any}", .{self.loadSegment});
        debug.printf("\n\tSystem Type:\t\t0x{x}", .{self.systemType});
        debug.printf("\n\tUnused1:\t\t0x{x}", .{self.unused1});
        debug.printf("\n\tSector Count:\t\t{d}", .{endian.readLittle(i16, &self.sectorCount)});
        debug.printf("\n\tLoad RBA:\t\t{d}", .{endian.readLittle(i32, &self.loadRba)});
        debug.printf("\n\tUnused2:\t\t{any}", .{self.unused2});
        debug.print("\n-------------------------------------------------------------------------------\n");
    }
};
