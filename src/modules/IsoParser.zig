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
    volumeDescriptorSetTerminator: bool = false,
};

pub fn parseIso(isoPath: []const u8) anyerror!void {
    const file: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer file.close();

    var isoBuffer: [ISO_SYS_BYTES_OFFSET]u8 = undefined;
    var volumeDescriptorsInitialized: VolumeDescriptorsInitialized = .{};
    var bootRecord: iso9660.BootRecord = undefined;
    // var bootCatalog: iso9660.BootCatalog = undefined;
    var primaryVolumeDescriptor: iso9660.PrimaryVolumeDescriptor = undefined;
    var volumeDescriptorSetTerminator: iso9660.VolumeDescriptorSetTerminator = undefined;

    const fileStat: std.fs.Dir.Stat = try file.stat();

    var byteCursor: u32 = 0;
    const isoSectorCount: u64 = fileStat.size / ISO_SECTOR_SIZE;

    const str =
        \\-------------------------- IsoParser ----------------------------
        \\ISO: {s}
        \\nISO size: {d}
        \\ISO sectors: {d}
        \\
    ;
    debug.printf(str, .{ isoPath, std.fmt.fmtIntSizeDec(fileStat.size), isoSectorCount });

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
                .standardIdentifier = sectorBuffer[1..6].*,
                .version = sectorBuffer[6],
                .bootSystemIdentifier = sectorBuffer[7..39].*,
                .bootIdentifier = sectorBuffer[39..71].*,
                .catalogLba = sectorBuffer[71..75].*,
                .unused = sectorBuffer[75..2048].*,
            };
            volumeDescriptorsInitialized.bootRecord = true;
        }

        if (sectorBuffer[0] == 1) {
            primaryVolumeDescriptor = .{
                .typeCode = sectorBuffer[0],
                .standardIdentifier = sectorBuffer[1..6].*,
                .version = sectorBuffer[6],
                .unused1 = sectorBuffer[7],
                .systemIdentifier = sectorBuffer[8..40].*,
                .volumeIdentifier = sectorBuffer[40..72].*,
                .unused2 = sectorBuffer[72..80].*,
                .volumeSpaceSize = sectorBuffer[80..88].*,
                .unused3 = sectorBuffer[88..120].*,
                .volumeSetSize = sectorBuffer[120..124].*,
                .volumeSequenceNumber = sectorBuffer[124..128].*,
                .logicalBlockSize = sectorBuffer[128..132].*,
                .pathTableSize = sectorBuffer[132..140].*,
                .locationOfTypeLPathTable = sectorBuffer[140..144].*,
                .locationOfOptionalTypeLPathTable = sectorBuffer[144..148].*,
                .locationOfTypeMPathTable = sectorBuffer[148..152].*,
                .locationOfOptionalTypeMPathTable = sectorBuffer[152..156].*,
                .rootDirectoryEntry = sectorBuffer[156..190].*,
                .volumeSetIdentifier = sectorBuffer[190..318].*,
                .publisherIdentifier = sectorBuffer[318..446].*,
                .dataPreparerIdentifier = sectorBuffer[446..574].*,
                .applicationIdentifier = sectorBuffer[574..702].*,
                .copyrightFileIdentifier = sectorBuffer[702..739].*,
                .abstractFileIdentifier = sectorBuffer[739..776].*,
                .bibliographicFileIdentifier = sectorBuffer[776..813].*,
                .volumeCreationDateTime = sectorBuffer[813..830].*,
                .volumeModificationDateTime = sectorBuffer[830..847].*,
                .volumeExpirationDateTime = sectorBuffer[847..864].*,
                .volumeEffectiveDateTime = sectorBuffer[864..881].*,
                .fileStructureVersion = sectorBuffer[881],
                .unused4 = sectorBuffer[882],
                .applicationUsed = sectorBuffer[883..1395].*,
                .reserved = sectorBuffer[1395..2048].*,
            };
            volumeDescriptorsInitialized.primaryVolumeDescriptor = true;
        }

        if (sectorBuffer[0] == 255) {
            volumeDescriptorSetTerminator = .{
                .typeCode = sectorBuffer[0],
                .standardIdentifier = sectorBuffer[1..6].*,
                .version = sectorBuffer[7],
            };
            volumeDescriptorsInitialized.volumeDescriptorSetTerminator = true;
        }

        if (volumeDescriptorsInitialized.bootRecord == true and volumeDescriptorsInitialized.primaryVolumeDescriptor == true and volumeDescriptorsInitialized.volumeDescriptorSetTerminator == true) break;
    }

    bootRecord.print();
    primaryVolumeDescriptor.print();
    volumeDescriptorSetTerminator.print();

    byteCursor = 0;
    const catalogLbaOffset: u32 = @bitCast(std.mem.readInt(i32, &bootRecord.catalogLba, std.builtin.Endian.little));
    try file.seekTo(ISO_SECTOR_SIZE * catalogLbaOffset);
    _ = try file.read(&sectorBuffer);
    // _ = bootCatalog;

    debug.print("\n\n-------------------------- Boot Catalog (El Torito Record) ---------------------------");

    debug.printf("\n\n::\tHeader Id:\t\t\t{d}", .{sectorBuffer[0]});
    debug.printf("\n::\tPlatform Id:\t\t\t{d}", .{sectorBuffer[1]});
    debug.printf("\n::\tReserved (0x00):\t\t0x{x}", .{sectorBuffer[2]});
    debug.printf("\n::\tReserved (0x00):\t\t0x{x}", .{sectorBuffer[3]});
    debug.printf("\n::\tManufacturer Identifier:\t{s}", .{sectorBuffer[4..27]});
    debug.printf("\n::\tChecksum:\t\t\t{s}", .{sectorBuffer[28..29]});
    debug.printf("\n::\tReserved (0x55):\t\t0x{x}", .{sectorBuffer[30]});
    debug.printf("\n::\tReserved (0xaa):\t\t0x{x}", .{sectorBuffer[31]});
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
