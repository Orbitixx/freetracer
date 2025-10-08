// Struct definitions for El Torito boot catalog records with debug printing
// helpers used while validating ISO images.
const std = @import("std");
const endian = @import("../util/endian.zig");
const Debug = @import("freetracer-lib").Debug;

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
        Debug.log(.DEBUG, "\n\n---------------------------- El Torito Validation Entry -----------------------------", .{});
        Debug.log(.DEBUG, "\n\tHeader ID:\t\t\t0x{x}", .{self.headerId});
        Debug.log(.DEBUG, "\n\tPlatform ID:\t\t\t0x{x}", .{self.platformId});
        Debug.log(.DEBUG, "\n\tReserved1:\t\t\t0x{x}", .{self.reserved1});
        Debug.log(.DEBUG, "\n\tReserved2:\t\t\t0x{x}", .{self.reserved2});
        Debug.log(.DEBUG, "\n\tManufacturer/Developer:\t{s}", .{self.manufacturerDev});
        Debug.log(.DEBUG, "\n\tChecksum:\t\t\t{any}", .{self.checksum});
        Debug.log(.DEBUG, "\n\tSignature 1:\t\t\t0x{x}", .{self.signature1});
        Debug.log(.DEBUG, "\n\tSignature 2:\t\t\t0x{x}", .{self.signature2});
        Debug.log(.DEBUG, "\n-------------------------------------------------------------------------------\n", .{});
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
        Debug.log(.DEBUG, "\n\n---------------------------- El Torito Initial/Default Entry ----------------------", .{});
        Debug.log(.DEBUG, "\n\tBoot Indicator:\t\t0x{x}", .{self.bootIndicator});
        Debug.log(.DEBUG, "\n\tBoot Media:\t\t{b:0>8}", .{self.bootMedia});
        Debug.log(.DEBUG, "\n\tLoad Segment:\t\t{any}", .{self.loadSegment});
        Debug.log(.DEBUG, "\n\tSystem Type:\t\t0x{x}", .{self.systemType});
        Debug.log(.DEBUG, "\n\tUnused1:\t\t0x{x}", .{self.unused1});
        Debug.log(.DEBUG, "\n\tSector Count:\t\t{d}", .{endian.readLittle(i16, &self.sectorCount)});
        Debug.log(.DEBUG, "\n\tLoad RBA:\t\t{d}", .{endian.readLittle(i32, &self.loadRba)});
        Debug.log(.DEBUG, "\n\tUnused2:\t\t{any}", .{self.unused2});
        Debug.log(.DEBUG, "\n-------------------------------------------------------------------------------\n", .{});
    }
};
