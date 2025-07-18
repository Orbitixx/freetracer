const std = @import("std");
const Debug = @import("freetracer-lib").Debug;
const endian = @import("../lib/util/endian.zig");
const iso9660 = @import("../lib/data/iso9660.zig");

const assert = std.debug.assert;

// ISO 9660: first 32kB are reserved system data (16 sectors, 2048 bytes wide)
const ISO_SYS_SECTORS: u32 = 16;
const ISO_SECTOR_SIZE: u32 = 2048;
const ISO_SYS_BYTES_OFFSET: u32 = ISO_SYS_SECTORS * ISO_SECTOR_SIZE;

const VolumeDescriptorsInitialized = struct {
    bootRecordVolumeDescriptor: bool = false,
    primaryVolumeDescriptor: bool = false,
    volumeDescriptorSetTerminator: bool = false,
};

pub const ISO_PARSER_RESULT = enum(u8) {
    ISO_VALID,
    ISO_SYSTEM_BLOCK_TOO_SHORT,
    ISO_SECTOR_TOO_SHORT,
    ISO_BOOT_OR_PVD_SECTOR_TOO_SHORT,
    ISO_INVALID_REQUIRED_VOLUME_DESCRIPTORS,
    ISO_INVALID_BOOT_INDICATOR,
    ISO_INVALID_BOOT_SIGNATURE,
    ISO_INVALID_BOOT_CATALOG,

    UNABLE_TO_OPEN_ISO_FILE,
    UNABLE_TO_OBTAIN_ISO_FILE_STAT,
    UNABLE_TO_READ_ISO_FILE,
    UNABLE_TO_SEEK_TO_SPECIFIED_SECTOR,
    INSUFFICIENT_DEVICE_CAPACITY,
};

pub fn parseIso(allocator: std.mem.Allocator, isoPath: []const u8, deviceSize: i64) ISO_PARSER_RESULT {
    _ = allocator;

    const file: std.fs.File = std.fs.cwd().openFile(isoPath, .{ .mode = .read_only }) catch |err| {
        Debug.log(.ERROR, "Unable to open the specified ISO file: {s}. Error: {any}", .{ isoPath, err });
        return ISO_PARSER_RESULT.UNABLE_TO_OPEN_ISO_FILE;
    };
    defer file.close();

    var isoBuffer: [ISO_SYS_BYTES_OFFSET]u8 = undefined;
    var bootRecordVolumeDescriptor: iso9660.BootRecord = undefined;
    var bootCatalog: iso9660.BootCatalog = undefined;
    var primaryVolumeDescriptor: iso9660.PrimaryVolumeDescriptor = undefined;
    var volumeDescriptorSetTerminator: iso9660.VolumeDescriptorSetTerminator = undefined;
    var volumeDescriptorsInitialized: VolumeDescriptorsInitialized = .{};

    const fileStat: std.fs.Dir.Stat = file.stat() catch |err| {
        Debug.log(.ERROR, "Unable to ontain ISO file stat: {s}. Error: {any}", .{ isoPath, err });
        return ISO_PARSER_RESULT.UNABLE_TO_OBTAIN_ISO_FILE_STAT;
    };

    if (fileStat.size > @as(u64, @intCast(deviceSize))) return ISO_PARSER_RESULT.INSUFFICIENT_DEVICE_CAPACITY;

    const isoSectorCount: u64 = fileStat.size / ISO_SECTOR_SIZE;

    const str =
        \\-------------------------- IsoParser ----------------------------
        \\ISO: {s}
        \\ISO size: {d}
        \\ISO sectors: {d}
        \\
    ;
    Debug.log(.DEBUG, str, .{ isoPath, std.fmt.fmtIntSizeDec(fileStat.size), isoSectorCount });

    const isoBytesRead = file.read(&isoBuffer) catch |err| {
        Debug.log(.ERROR, "Unable to read the specified ISO file: {s}. Error: {any}", .{ isoPath, err });
        return ISO_PARSER_RESULT.UNABLE_TO_READ_ISO_FILE;
    };

    if (isoBytesRead < ISO_SYS_BYTES_OFFSET) {
        Debug.log(.ERROR, "ISO system block is shorter than ISO 9660 spec.", .{});
        return ISO_PARSER_RESULT.ISO_SYSTEM_BLOCK_TOO_SHORT;
    }

    var sectorBuffer: [ISO_SECTOR_SIZE]u8 = undefined;

    for (16..isoSectorCount) |i| {
        Debug.log(.DEBUG, "IsoParser: Parsing ISO sector:\t{d}", .{i});

        file.seekTo(ISO_SYS_BYTES_OFFSET + ISO_SECTOR_SIZE * (i - 16)) catch |err| {
            Debug.log(.ERROR, "Unable to read the specified ISO file: {s}. Error: {any}", .{ isoPath, err });
            return ISO_PARSER_RESULT.UNABLE_TO_SEEK_TO_SPECIFIED_SECTOR;
        };

        const sectorBytesRead = file.read(&sectorBuffer) catch |err| {
            Debug.log(.ERROR, "Unable to read ISO sector: {d}. Error: {any}", .{ ISO_SYS_BYTES_OFFSET + ISO_SECTOR_SIZE * (i - 16), err });
            return ISO_PARSER_RESULT.UNABLE_TO_OPEN_ISO_FILE;
        };

        if (sectorBytesRead < ISO_SECTOR_SIZE) {
            Debug.log(.ERROR, "ISO Sector bytes read are shorter than the sector size.", .{});
            return ISO_PARSER_RESULT.ISO_SECTOR_TOO_SHORT;
        }

        if (sectorBuffer[0] == 0) {
            bootRecordVolumeDescriptor = .{
                .typeCode = sectorBuffer[0],
                .standardIdentifier = sectorBuffer[1..6].*,
                .version = sectorBuffer[6],
                .bootSystemIdentifier = sectorBuffer[7..39].*,
                .bootIdentifier = sectorBuffer[39..71].*,
                .catalogLba = sectorBuffer[71..75].*,
                .unused = sectorBuffer[75..2048].*,
            };
            volumeDescriptorsInitialized.bootRecordVolumeDescriptor = true;
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

        if (volumeDescriptorsInitialized.bootRecordVolumeDescriptor == true and
            volumeDescriptorsInitialized.primaryVolumeDescriptor == true and
            volumeDescriptorsInitialized.volumeDescriptorSetTerminator == true)
        {
            break;
        }
    }

    if (volumeDescriptorsInitialized.bootRecordVolumeDescriptor == false or
        volumeDescriptorsInitialized.primaryVolumeDescriptor == false or
        volumeDescriptorsInitialized.volumeDescriptorSetTerminator == false)
    {
        return ISO_PARSER_RESULT.ISO_INVALID_REQUIRED_VOLUME_DESCRIPTORS;
    }

    bootCatalog = readBootCatalog(&file, bootRecordVolumeDescriptor.catalogLba) catch |err| {
        Debug.log(.ERROR, "ISO has an invalid boot catalog. Error: {any}", .{err});
        return ISO_PARSER_RESULT.ISO_INVALID_BOOT_CATALOG;
    };

    if (bootCatalog.initialDefaultEntry.bootIndicator != 0x88)
        return ISO_PARSER_RESULT.ISO_INVALID_BOOT_INDICATOR;
    if (bootCatalog.validationEntry.signature1 != 0x55 or bootCatalog.validationEntry.signature2 != 0xaa)
        return ISO_PARSER_RESULT.ISO_INVALID_BOOT_SIGNATURE;

    // bootRecordVolumeDescriptor.print();
    // bootCatalog.print();
    // primaryVolumeDescriptor.print();
    // volumeDescriptorSetTerminator.print();

    // const rootDirectoryEntry = iso9660.DirectoryRecord().init(&primaryVolumeDescriptor.rootDirectoryEntry);
    // rootDirectoryEntry.print();

    const loadRbaSectorOffset: u32 = @bitCast(endian.readLittle(i32, &bootCatalog.initialDefaultEntry.loadRba) + 16);

    file.seekTo(ISO_SECTOR_SIZE * loadRbaSectorOffset) catch |err| {
        Debug.log(.ERROR, "Unable to seek to sector [Load RBA Sector Offset]: {d}. Error: {any}", .{ ISO_SECTOR_SIZE * loadRbaSectorOffset, err });
        return ISO_PARSER_RESULT.UNABLE_TO_SEEK_TO_SPECIFIED_SECTOR;
    };

    _ = file.read(&sectorBuffer) catch |err| {
        Debug.log(.ERROR, "Unable to read ISO sector [Load RBA Sector Offset]: {d}. Error: {any}", .{ ISO_SECTOR_SIZE * loadRbaSectorOffset, err });
        return ISO_PARSER_RESULT.UNABLE_TO_READ_ISO_FILE;
    };

    // const loadRbaSector = iso9660.DirectoryRecord().init(&sectorBuffer);
    // loadRbaSector.print();

    // try walkDirectories(allocator, &file, @bitCast(endian.readBoth(i32, &rootDirectoryEntry.dataLength)), @bitCast(endian.readBoth(i32, &rootDirectoryEntry.locationOfExtent)));

    return ISO_PARSER_RESULT.ISO_VALID;
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
            .signature1 = bootCatalogSectorBuffer[30],
            .signature2 = bootCatalogSectorBuffer[31],
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

pub const DirectoryEntry = struct {
    size: u32,
    lba: u32,
    flags: u8,
    nameLength: u8,
    name: []u8,
    isDir: bool,
};

pub fn walkDirectories(allocator: std.mem.Allocator, pFile: *const std.fs.File, dataLength: u32, offsetLba: u32) !void {
    Debug.log(.DEBUG, "\n-------------------- BEGIN DIRECTORY WALKTHROUGH --------------------");
    Debug.log(.DEBUG, "\tData Length: {d}\n\tOffset LBA: {d}\n\n", .{ dataLength, offsetLba });

    var buffer: []u8 = try allocator.alloc(u8, dataLength);
    defer allocator.free(buffer);

    var dirEntries = std.ArrayList(DirectoryEntry).init(allocator);
    defer dirEntries.deinit();

    try pFile.*.seekTo(ISO_SECTOR_SIZE * offsetLba);
    _ = try pFile.*.read(buffer);

    var byteOffset: u64 = 0;

    while (byteOffset < buffer.len) {
        const recordLength = buffer[byteOffset];

        if (recordLength == 0) break;

        var lbaArray: [8]u8 = undefined;
        @memcpy(&lbaArray, buffer[(byteOffset + 2)..(byteOffset + 10)]);
        const lba: u32 = @bitCast(endian.readBoth(i32, &lbaArray));

        var sizeArray: [8]u8 = undefined;
        @memcpy(&sizeArray, buffer[(byteOffset + 10)..(byteOffset + 18)]);
        const size: u32 = @bitCast(endian.readBoth(i32, &sizeArray));

        const flags = buffer[byteOffset + 25];
        const nameLength = buffer[byteOffset + 32];
        const name = buffer[byteOffset + 33 .. byteOffset + 33 + nameLength];

        const dirType = if ((flags & 0x02) != 0) "DIR" else "FILE";

        const newDir = DirectoryEntry{
            .name = name,
            .nameLength = nameLength,
            .size = size,
            .lba = lba,
            .flags = flags,
            .isDir = if ((flags & 0x02) != 0) true else false,
        };

        // Filter out "." and ".." directories
        if (name[0] != 0x00 and name[0] != 0x01) {
            try dirEntries.append(newDir);

            const str =
                \\[{s}] {s} at LBA {d} ({d} bytes)
            ;

            Debug.log(.DEBUG, str, .{ dirType, name, lba, size });
        }

        byteOffset += recordLength;

        // Directory records are 0-padded to begin on an even byte
        if (byteOffset % 2 != 0) byteOffset += 1;
    }

    for (0..dirEntries.items.len) |i| {
        if (dirEntries.items[i].isDir == true) try walkDirectories(allocator, pFile, dirEntries.items[i].size, dirEntries.items[i].lba);
    }
}

pub fn walkDirectory(buffer: *const []u8, dirEntries: *std.ArrayList(DirectoryEntry)) !void {
    var byteOffset: u64 = 0;

    while (byteOffset < buffer.len) {
        const recordLength = buffer[byteOffset];

        if (recordLength == 0) break;

        var lbaArray: [8]u8 = undefined;
        @memcpy(&lbaArray, buffer[(byteOffset + 2)..(byteOffset + 10)]);

        const lba = endian.readBoth(i32, &lbaArray);

        var sizeArray: [8]u8 = undefined;
        @memcpy(&sizeArray, buffer[(byteOffset + 10)..(byteOffset + 18)]);

        const size = endian.readBoth(i32, &sizeArray);
        const flags = buffer[byteOffset + 25];
        const nameLength = buffer[byteOffset + 32];
        const name = buffer[byteOffset + 33 .. byteOffset + 33 + nameLength];

        const dirType = if ((flags & 0x02) != 0) "DIR" else "FILE";

        const newDir = DirectoryEntry{
            .name = name,
            .nameLength = nameLength,
            .size = size,
            .lba = lba,
            .flags = flags,
            .isDir = if ((flags & 0x02) != 0) true else false,
        };

        // Filter out "." and ".." directories
        if (name[0] != 0x00 and name[0] != 0x01) {
            try dirEntries.*.append(newDir);

            const str =
                \\[{s}] {s} at LBA {d} ({d} bytes)
            ;

            Debug.log(.DEBUG, str, .{ dirType, name, lba, size });
        }

        byteOffset += recordLength;

        // Directory records are 0-padded to begin on an even byte
        if (byteOffset % 2 != 0) byteOffset += 1;
    }
}
