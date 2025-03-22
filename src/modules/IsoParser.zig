const std = @import("std");
const debug = @import("../lib/util/debug.zig");
const endian = @import("../lib/util/endian.zig");
const iso9660 = @import("../lib/data/iso9660.zig");

// ISO 9660: first 32kB are reserved system data (16 sectors, 2048 bytes wide)
const ISO_SYS_SECTORS: u32 = 16;
const ISO_SECTOR_SIZE: u32 = 2048;
const ISO_SYS_BYTES_OFFSET: u32 = ISO_SYS_SECTORS * ISO_SECTOR_SIZE;

const VolumeDescriptorsInitialized = struct {
    bootRecord: bool = false,
    primaryVolumeDescriptor: bool = false,
};

pub fn parseIso(isoPath: []const u8) anyerror!void {
    const file: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer file.close();

    var isoBuffer: [ISO_SYS_BYTES_OFFSET]u8 = undefined;
    var volumeDescriptorsInitialized: VolumeDescriptorsInitialized = .{};
    var bootRecord: iso9660.BootRecord = undefined;
    var primaryVolumeDescriptor: iso9660.PrimaryVolumeDescriptor = undefined;

    const fileStat: std.fs.Dir.Stat = try file.stat();

    var byteCursor: u32 = 0;
    const isoSectorCount: u64 = fileStat.size / ISO_SECTOR_SIZE;

    debug.print("\n-------------------------- IsoParser ----------------------------");
    debug.printf("\nISO: {s}", .{isoPath});
    debug.printf("\nISO size: {d}", .{std.fmt.fmtIntSizeDec(fileStat.size)});
    debug.printf("\nISO sectors: {d}\n", .{isoSectorCount});

    const isoBytesRead = try file.read(&isoBuffer);

    if (isoBytesRead < ISO_SYS_BYTES_OFFSET) {
        return IsoParserError.IsoSystemBlockTooShort;
    }

    var sectorBuffer: [ISO_SECTOR_SIZE]u8 = undefined;

    for (16..isoSectorCount) |i| {
        debug.printf("\n:: IsoParser: Parsing ISO sector:\t{d}", .{i});

        try file.seekTo(ISO_SYS_BYTES_OFFSET + ISO_SECTOR_SIZE * (i - 16));
        const sectorBytesRead = try file.read(&sectorBuffer);

        if (sectorBytesRead < ISO_SECTOR_SIZE) {
            return IsoParserError.IsoSectorTooShort;
        }

        if (sectorBuffer[0] == 0) {
            bootRecord = .{
                .typeCode = sectorBuffer[0],
                .identifier = sectorBuffer[1..6].*,
                .version = sectorBuffer[6],
                .bootSystemIdentifier = sectorBuffer[7..39].*,
                .bootIdentifier = sectorBuffer[39..71].*,
                .catalogLba = sectorBuffer[71..75].*,
                .unused = sectorBuffer[75..2048].*,
            };
            volumeDescriptorsInitialized.bootRecord = true;
        }

        if (sectorBuffer[0] == 1) {
            primaryVolumeDescriptor = .{};
            volumeDescriptorsInitialized.primaryVolumeDescriptor = true;
        }

        if (volumeDescriptorsInitialized.bootRecord == true and volumeDescriptorsInitialized.primaryVolumeDescriptor == true) break;
    }

    bootRecord.print();

    byteCursor = 0;
    try file.seekTo(ISO_SYS_BYTES_OFFSET + ISO_SECTOR_SIZE);
    _ = try file.read(&sectorBuffer);

    // debug.printf("\n::\tVolume Descriptor Type:\t\t{d}", .{bootRecord.typeCode});
    // debug.printf("\n::\tCD001 Identifier:\t\t{s}", .{bootRecord.identifier});
    // debug.printf("\n::\tVolume Descriptor Version:\t{x}", .{bootRecord.version});
    // debug.printf("\n::\tBoot System Identifier:\t\t{s}", .{bootRecord.bootSystemIdentifier});
    // debug.printf("\n::\tBoot Identifier:\t\t{s}", .{bootRecord.bootIdentifier});
    // debug.printf("\n::\tBoot Catalog LBA:\t\t{d}\n", .{std.mem.readInt(i32, &bootRecord.catalogLba, std.builtin.Endian.little)});

    // var endBuffer: [4]u8 = undefined;
    // @memcpy(&endBuffer, readBytes(&byteCursor, &sectorBuffer, 4));
    // const elTorRecord: u32 = @bitCast(std.mem.readInt(i32, &endBuffer, std.builtin.Endian.little));
    //
    // debug.printf("\n::\tEl Torito Record:\t\t{d}\n", .{elTorRecord});
    //
    // byteCursor = 0;
    // try file.seekTo(ISO_SECTOR_SIZE * elTorRecord);
    // _ = try file.read(&sectorBuffer);
    //
    // debug.printf("\n\n::\tHeader Id:\t\t\t{d}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    // debug.printf("\n::\tPlatform Id:\t\t\t{d}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    // debug.printf("\n::\tReserved (0x00):\t\t0x{x}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    // debug.printf("\n::\tReserved (0x00):\t\t0x{x}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    // debug.printf("\n::\tManufacturer Identifier:\t{any}", .{readBytes(&byteCursor, &sectorBuffer, 24)});
    // debug.printf("\n::\tChecksum:\t\t\t{s}", .{readBytes(&byteCursor, &sectorBuffer, 2)});
    // debug.printf("\n::\tReserved (0x55):\t\t0x{x}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    // debug.printf("\n::\tReserved (0xaa):\t\t0x{x}", .{readBytes(&byteCursor, &sectorBuffer, 1)[0]});
    //
    debug.print("\n");

    // if (bootSignature != 0x5553) { // "SS" in ASCII
    //     return error.InvalidIsoFile;
    // }
    //
    // var bootType: BootType =32 .Unknown;
    // if (bootMethod == 0x00) {
    //     bootType = .Bios;
    // } else if (bootMethod == 0x02) {
    //     bootType = .Uefi;
    // }
    //
    // std.log.info("ISO Boot Type: {D}", .{bootType});
    //
    // return file; // Return the file object for further processing
}

// Enum to represent the boot type
pub const BootType = enum {
    Bios,
    Uefi,
    Unknown,
};

pub const IsoParserError = error{
    IsoSystemBlockTooShort,
    IsoSectorTooShort,
};

pub fn readBytes(byteCursor: *u32, buffer: []const u8, len: u32) []const u8 {
    var finalSlice: []const u8 = undefined;
    finalSlice = buffer[byteCursor.* .. byteCursor.* + len];
    byteCursor.* = byteCursor.* + len;

    return finalSlice;
}
