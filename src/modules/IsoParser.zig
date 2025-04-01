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
    var bootRecord: iso9660.BootRecord = undefined;
    var bootCatalog: iso9660.BootCatalog = undefined;
    var primaryVolumeDescriptor: iso9660.PrimaryVolumeDescriptor = undefined;
    var volumeDescriptorSetTerminator: iso9660.VolumeDescriptorSetTerminator = undefined;
    var volumeDescriptorsInitialized: VolumeDescriptorsInitialized = .{};

    const fileStat: std.fs.Dir.Stat = try file.stat();

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

        if (volumeDescriptorsInitialized.bootRecord == true and
            volumeDescriptorsInitialized.primaryVolumeDescriptor == true and
            volumeDescriptorsInitialized.volumeDescriptorSetTerminator == true)
        {
            break;
        }
    }

    if (volumeDescriptorsInitialized.bootRecord == false or
        volumeDescriptorsInitialized.primaryVolumeDescriptor == false or
        volumeDescriptorsInitialized.volumeDescriptorSetTerminator == false)
    {
        return error.IsoParserUnableToParseIsoMimimumNecessaryDescriptors;
    }

    bootCatalog = try readBootCatalog(&file, bootRecord.catalogLba);

    bootRecord.print();
    bootCatalog.print();
    primaryVolumeDescriptor.print();
    volumeDescriptorSetTerminator.print();

    const rootDirectoryEntry: iso9660.DirectoryRecord = .{
        .lengthOfDirectoryRecord = primaryVolumeDescriptor.rootDirectoryEntry[0],
        .lengthOfExtendedAttributeRecord = primaryVolumeDescriptor.rootDirectoryEntry[1],
        .locationOfExtent = primaryVolumeDescriptor.rootDirectoryEntry[2..10].*,
        .fileFlags = primaryVolumeDescriptor.rootDirectoryEntry[25],
        .lengthOfFileIdentifier = primaryVolumeDescriptor.rootDirectoryEntry[32],
        .fileIdentifier = primaryVolumeDescriptor.rootDirectoryEntry[33],
    };

    rootDirectoryEntry.print();

    const rootDirExtentOffset: u32 = @bitCast(endian.readBoth(i32, &rootDirectoryEntry.locationOfExtent));
    try file.seekTo(ISO_SECTOR_SIZE * rootDirExtentOffset);
    _ = try file.read(&sectorBuffer);

    const rootDirExtent: iso9660.DirectoryRecord = .{
        .lengthOfDirectoryRecord = sectorBuffer[0],
        .lengthOfExtendedAttributeRecord = sectorBuffer[1],
        .locationOfExtent = sectorBuffer[2..10].*,
        .fileFlags = sectorBuffer[25],
        .lengthOfFileIdentifier = sectorBuffer[32],
        .fileIdentifier = sectorBuffer[33],
    };

    rootDirExtent.print();

    const loadRbaSectorOffset: u32 = @bitCast(endian.readLittle(i32, &bootCatalog.initialDefaultEntry.loadRba));
    try file.seekTo(ISO_SECTOR_SIZE * loadRbaSectorOffset);
    _ = try file.read(&sectorBuffer);

    const loadRbaSector: iso9660.DirectoryRecord = .{
        .lengthOfDirectoryRecord = sectorBuffer[0],
        .lengthOfExtendedAttributeRecord = sectorBuffer[1],
        .locationOfExtent = sectorBuffer[2..10].*,
        .fileFlags = sectorBuffer[25],
        .lengthOfFileIdentifier = sectorBuffer[32],
        .fileIdentifier = sectorBuffer[33],
    };

    loadRbaSector.print();

    debug.print("\n");
}
pub const IsoParserError = error{
    IsoSystemBlockTooShort,
    IsoSectorTooShort,
};

pub fn readBootCatalog(pFile: *const std.fs.File, catalogLba: [4]u8) !iso9660.BootCatalog {
    var bootCatalogSectorBuffer: [2048]u8 = undefined;

    const catalogLbaOffset: u32 = @bitCast(endian.readLittle(i32, &catalogLba));

    try pFile.*.seekTo(ISO_SECTOR_SIZE * catalogLbaOffset);
    _ = try pFile.*.read(&bootCatalogSectorBuffer);

    const bootCatalog: iso9660.BootCatalog = .{
        .validationEntry = .{
            .headerId = bootCatalogSectorBuffer[0],
            .platformId = bootCatalogSectorBuffer[1],
            .reserved1 = bootCatalogSectorBuffer[2],
            .reserved2 = bootCatalogSectorBuffer[3],
            .manufacturerDev = bootCatalogSectorBuffer[4..28].*,
            .checksum = bootCatalogSectorBuffer[28..30].*,
            .reserved3 = bootCatalogSectorBuffer[30],
            .reserved4 = bootCatalogSectorBuffer[31],
        },

        .initialDefaultEntry = .{
            .bootIndicator = bootCatalogSectorBuffer[32],
            .bootMedia = bootCatalogSectorBuffer[33],
            .loadSegment = bootCatalogSectorBuffer[34..36].*,
            .systemType = bootCatalogSectorBuffer[36],
            .unused1 = bootCatalogSectorBuffer[37],
            .sectorCount = bootCatalogSectorBuffer[38..40].*,
            .loadRba = bootCatalogSectorBuffer[40..44].*,
            .unused2 = bootCatalogSectorBuffer[44..64].*,
        },

        .optional = bootCatalogSectorBuffer[64..2048].*,
    };

    return bootCatalog;
}
