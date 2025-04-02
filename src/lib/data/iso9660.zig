const std = @import("std");
const eltorito = @import("eltorito.zig");
const endian = @import("../util/endian.zig");
const debug = @import("../util/debug.zig");

pub const PrimaryVolumeDescriptor = struct {
    /// int8
    typeCode: u8, // Always 0x01
    /// strA
    standardIdentifier: [5]u8, // Always 'CD001'
    /// int8
    version: u8, // Always 0x01
    /// Unused
    unused1: u8, // Always 0x00
    /// strA
    systemIdentifier: [32]u8, // Name of the system
    /// strD
    volumeIdentifier: [32]u8, // Volume ID
    /// Unused Field
    unused2: [8]u8, // All zeroes
    /// int32_LSB-MSB
    volumeSpaceSize: [8]u8, // Number of Logical Blocks
    /// Unused Field
    unused3: [32]u8, // All zeroes
    /// int16_LSB-MSB
    volumeSetSize: [4]u8, // Size of the set in this logical volume
    /// int16_LSB-MSB
    volumeSequenceNumber: [4]u8, // Number of this disk in the Volume Set
    /// int16_LSB-MSB
    logicalBlockSize: [4]u8, // Size in bytes of a logical block
    /// int32_LSB-MSB
    pathTableSize: [8]u8, // Size in bytes of the path table
    /// int32_LSB
    locationOfTypeLPathTable: [4]u8, // LBA location of the path table (little-endian)
    /// int32_LSB
    locationOfOptionalTypeLPathTable: [4]u8, // LBA location of optional path table (little-endian)
    /// int32_MSB
    locationOfTypeMPathTable: [4]u8, // LBA location of the path table (big-endian)
    /// int32_MSB
    locationOfOptionalTypeMPathTable: [4]u8, // LBA location of optional path table (big-endian)
    /// Directory entry
    rootDirectoryEntry: [34]u8, // Root directory record
    /// strD
    volumeSetIdentifier: [128]u8, // Volume Set ID
    /// strA
    publisherIdentifier: [128]u8, // Publisher ID
    /// strA
    dataPreparerIdentifier: [128]u8, // Data Preparer ID
    /// strA
    applicationIdentifier: [128]u8, // Application ID
    /// strD
    copyrightFileIdentifier: [37]u8, // Copyright File
    /// strD
    abstractFileIdentifier: [37]u8, // Abstract File
    /// strD
    bibliographicFileIdentifier: [37]u8, // Bibliographic File
    /// dec-datetime
    volumeCreationDateTime: [17]u8, // Creation Date-Time
    /// dec-datetime
    volumeModificationDateTime: [17]u8, // Modification Date-Time
    /// dec-datetime
    volumeExpirationDateTime: [17]u8, // Expiration Date-Time
    /// dec-datetime
    volumeEffectiveDateTime: [17]u8, // Effective Date-Time
    /// int8
    fileStructureVersion: u8, // Always 0x01
    /// Unused
    unused4: u8, // Always 0x00
    /// Application-specific
    applicationUsed: [512]u8, // Undefined contents
    /// Reserved
    reserved: [653]u8, // Reserved by ISO

    pub fn print(self: @This()) void {
        debug.print("\n\n-------------------------- Primary Volume Descriptor ---------------------------");
        debug.printf("\n\tType Code:\t\t\t{d}", .{self.typeCode});
        debug.printf("\n\tStandard Identifier:\t\t{s}", .{self.standardIdentifier});
        debug.printf("\n\tVersion:\t\t\t{d}", .{self.version});
        debug.printf("\n\tUnused1:\t\t\t0x{x}", .{self.unused1});
        debug.printf("\n\tSystem Identifier:\t\t{s}", .{self.systemIdentifier});
        debug.printf("\n\tVolume Identifier:\t\t{s}", .{self.volumeIdentifier});
        debug.printf("\n\tUnused2:\t\t\t{any}", .{self.unused2});
        debug.printf("\n\tVolume Space Size:\t\t{any}", .{self.volumeSpaceSize});
        debug.printf("\n\tUnused3:\t\t\t{any}", .{self.unused3});
        debug.printf("\n\tVolume Set Size:\t\t{any}", .{self.volumeSetSize});
        debug.printf("\n\tVolume Sequence Number:\t{any}", .{self.volumeSequenceNumber});
        debug.printf("\n\tLogical Block Size:\t{any}", .{self.logicalBlockSize});
        debug.printf("\n\tPath Table Size:\t\t{any}", .{self.pathTableSize});
        debug.printf("\n\tLocation of Type-L Path Table:\t\t{any}", .{self.locationOfTypeLPathTable});
        debug.printf("\n\tLocation of Optional Type-L Path Table:\t\t{any}", .{self.locationOfOptionalTypeLPathTable});
        debug.printf("\n\tLocation of Type-M Path Table:\t\t{any}", .{self.locationOfTypeMPathTable});
        debug.printf("\n\tLocation of Optional Type-M Path Table:\t\t{any}", .{self.locationOfOptionalTypeMPathTable});
        debug.printf("\n\tRoot Directory Entry:\t\t{any}", .{self.rootDirectoryEntry});
        debug.printf("\n\tVolume Set Identifier:\t\t{s}", .{self.volumeSetIdentifier});
        debug.printf("\n\tPublisher Identifier:\t\t{s}", .{self.publisherIdentifier});
        debug.printf("\n\tData Preparer Identifier:\t\t{s}", .{self.dataPreparerIdentifier});
        debug.printf("\n\tApplication Identifier:\t{s}", .{self.applicationIdentifier});
        debug.printf("\n\tCopyright File Identifier:\t{s}", .{self.copyrightFileIdentifier});
        debug.printf("\n\tAbstract File Identifier:\t{s}", .{self.abstractFileIdentifier});
        debug.printf("\n\tBibliographic File Identifier:\t{s}", .{self.bibliographicFileIdentifier});
        debug.printf("\n\tVolume Creation Date/Time:\t{s}", .{self.volumeCreationDateTime});
        debug.printf("\n\tVolume Modification Date/Time:\t{s}", .{self.volumeModificationDateTime});
        debug.printf("\n\tVolume Expiration Date/Time:\t{s}", .{self.volumeExpirationDateTime});
        debug.printf("\n\tVolume Effective Date/Time:\t{s}", .{self.volumeEffectiveDateTime});
        debug.printf("\n\tFile Structure Version:\t{d}", .{self.fileStructureVersion});
        debug.printf("\n\tUnused4:\t\t\t0x{x}", .{self.unused4});
        debug.printf("\n\tApplication Used:\t{any}", .{self.applicationUsed});
        debug.printf("\n\tReserved:\t\t{any}", .{self.reserved});
        debug.print("\n-------------------------------------------------------------------------------\n");
    }

    pub fn printAuto(self: @This()) void {
        inline for (std.meta.fields(@TypeOf(self))) |field| {
            debug.printf("\n\t{s}:\t\t\t\t{any}", .{ field.name, @as(field.type, @field(self, field.name)) });

            // switch (@typeInfo(field.type)) {
            //     .Pointer, .Array => debug.printf("{s}", @as(field.type, @field(self, field.name))),
            //     .Int => debug.printf("{d}", @as(field.type, @field(self, field.name))),
            //     else => debug.printf("{any}", @as(field.type, @field(self, field.name))),
            // }
        }
    }
};

pub const BootRecord = struct {
    /// int8
    typeCode: u8, // Always 0x01
    /// strA
    standardIdentifier: [5]u8, // Always 'CD001'
    /// int8
    version: u8, // Always 0x01
    /// strA
    bootSystemIdentifier: [32]u8,
    /// strA
    bootIdentifier: [32]u8,

    // El Torito Spec
    /// int32_LSB - points to the BootCatalog, little-endian 32 bit int
    catalogLba: [4]u8,
    unused: [1973]u8,

    pub fn print(self: @This()) void {
        debug.print("\n\n-------------------------- Boot Record ---------------------------");
        debug.printf("\n\tType Code:\t\t\t{d}", .{self.typeCode});
        debug.printf("\n\tIdentifier:\t\t\t{s}", .{self.standardIdentifier});
        debug.printf("\n\tVersion:\t\t\t{d}", .{self.version});
        debug.printf("\n\tBoot System Identifier:\t\t{s}", .{self.bootSystemIdentifier});
        debug.printf("\n\tBoot Identifier:\t\t{s}", .{self.bootIdentifier});
        debug.printf("\n\tCatalog LBA:\t\t\t{d}\n", .{endian.readLittle(i32, &self.catalogLba)});
        debug.print("\n-------------------------------------------------------------------------------\n");
    }
};

pub const BootCatalog = struct {
    validationEntry: eltorito.ValidationEntry, // 32b wide
    initialDefaultEntry: eltorito.InitialDefaultEntry, // 32b wide

    // Optional sector head and entries
    // https://dev.lovelyhq.com/libburnia/libisofs/raw/branch/master/doc/boot_sectors.txt
    optional: [1984]u8,

    pub fn print(self: @This()) void {
        self.validationEntry.print();
        self.initialDefaultEntry.print();
    }
};

pub const VolumeDescriptorSetTerminator = struct {
    /// int8
    typeCode: u8, // Always 0x01
    /// strA
    standardIdentifier: [5]u8, // Always 'CD001'
    /// int8
    version: u8, // Always 0x01

    pub fn print(self: @This()) void {
        debug.print("\n\n-------------------------- Volume Descriptor Set Terminator ---------------------------");
        debug.printf("\n\tType Code:\t\t\t{d}", .{self.typeCode});
        debug.printf("\n\tIdentifier:\t\t\t{s}", .{self.standardIdentifier});
        debug.printf("\n\tVersion:\t\t\t{d}\n", .{self.version});
    }
};

pub fn DirectoryRecord() type {
    return struct {
        /// int8
        lengthOfDirectoryRecord: u8,
        /// int8
        lengthOfExtendedAttributeRecord: u8,
        /// int32_LSB-MSB (LBA)
        locationOfExtent: [8]u8,
        /// int32_LSB-MSB
        dataLength: [8]u8,
        /// 7b
        recordingDateTime: ?[7]u8 = null,
        /// u8
        fileFlags: u8,
        /// int8
        fileUnitSize: ?u8 = null,
        /// int8
        interleaveGapSize: ?u8 = null,
        /// int16_LSB-MSB
        volumeSequenceNumber: ?[4]u8 = null,
        /// int8
        lengthOfFileIdentifier: u8,
        /// strD
        fileIdentifier: u8,
        /// --
        paddingField: ?u8 = null,

        pub fn init(buffer: []const u8) @This() {
            return .{
                .lengthOfDirectoryRecord = @bitCast(buffer[0]),
                .lengthOfExtendedAttributeRecord = @bitCast(buffer[1]),
                .locationOfExtent = buffer[2..10].*,
                .dataLength = buffer[10..18].*,
                .fileFlags = @bitCast(buffer[25]),
                .lengthOfFileIdentifier = @bitCast(buffer[32]),
                .fileIdentifier = @bitCast(buffer[33]),
            };
        }

        pub fn print(self: @This()) void {
            debug.print("\n----------------- Directory Record ---------------------");
            debug.printf("\n\tLength of Dir Record:\t\t\t{d}", .{self.lengthOfDirectoryRecord});
            debug.printf("\n\tLength of Ext Attr Record:\t\t{d}", .{self.lengthOfExtendedAttributeRecord});
            debug.printf("\n\tLocation of Extent:\t\t\t{d}", .{endian.readBoth(i32, &self.locationOfExtent)});
            debug.printf("\n\tData Length:\t\t\t{d}", .{endian.readBoth(i32, &self.dataLength)});
            debug.printf("\n\tFile Flags:\t\t\t{b:0>8}", .{self.fileFlags});
            debug.printf("\n\tLength of File Identifier:\t\t{d}", .{self.lengthOfFileIdentifier});
            debug.printf("\n\tfileIdentifier:\t\t\t{x}", .{self.fileIdentifier});
            debug.print("\n");
        }
    };
}
