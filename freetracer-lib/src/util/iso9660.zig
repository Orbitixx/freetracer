const std = @import("std");
const eltorito = @import("eltorito.zig");
const endian = @import("../util/endian.zig");
const Debug = @import("freetracer-lib").Debug;

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
        Debug.log(.DEBUG, "-------------------------- Primary Volume Descriptor ---------------------------", .{});
        Debug.log(.DEBUG, "\tType Code:\t\t\t{d}", .{self.typeCode});
        Debug.log(.DEBUG, "\tStandard Identifier:\t\t{s}", .{self.standardIdentifier});
        Debug.log(.DEBUG, "\tVersion:\t\t\t{d}", .{self.version});
        Debug.log(.DEBUG, "\tUnused1:\t\t\t0x{x}", .{self.unused1});
        Debug.log(.DEBUG, "\tSystem Identifier:\t\t{s}", .{self.systemIdentifier});
        Debug.log(.DEBUG, "\tVolume Identifier:\t\t{s}", .{self.volumeIdentifier});
        Debug.log(.DEBUG, "\tUnused2:\t\t\t{any}", .{self.unused2});
        Debug.log(.DEBUG, "\tVolume Space Size:\t\t{any}", .{self.volumeSpaceSize});
        Debug.log(.DEBUG, "\tUnused3:\t\t\t{any}", .{self.unused3});
        Debug.log(.DEBUG, "\tVolume Set Size:\t\t{any}", .{self.volumeSetSize});
        Debug.log(.DEBUG, "\tVolume Sequence Number:\t{any}", .{self.volumeSequenceNumber});
        Debug.log(.DEBUG, "\tLogical Block Size:\t{any}", .{self.logicalBlockSize});
        Debug.log(.DEBUG, "\tPath Table Size:\t\t{any}", .{self.pathTableSize});
        Debug.log(.DEBUG, "\tLocation of Type-L Path Table:\t\t{any}", .{self.locationOfTypeLPathTable});
        Debug.log(.DEBUG, "\tLocation of Optional Type-L Path Table:\t\t{any}", .{self.locationOfOptionalTypeLPathTable});
        Debug.log(.DEBUG, "\tLocation of Type-M Path Table:\t\t{any}", .{self.locationOfTypeMPathTable});
        Debug.log(.DEBUG, "\tLocation of Optional Type-M Path Table:\t\t{any}", .{self.locationOfOptionalTypeMPathTable});
        Debug.log(.DEBUG, "\tRoot Directory Entry:\t\t{any}", .{self.rootDirectoryEntry});
        Debug.log(.DEBUG, "\tVolume Set Identifier:\t\t{s}", .{self.volumeSetIdentifier});
        Debug.log(.DEBUG, "\tPublisher Identifier:\t\t{s}", .{self.publisherIdentifier});
        Debug.log(.DEBUG, "\tData Preparer Identifier:\t\t{s}", .{self.dataPreparerIdentifier});
        Debug.log(.DEBUG, "\tApplication Identifier:\t{s}", .{self.applicationIdentifier});
        Debug.log(.DEBUG, "\tCopyright File Identifier:\t{s}", .{self.copyrightFileIdentifier});
        Debug.log(.DEBUG, "\tAbstract File Identifier:\t{s}", .{self.abstractFileIdentifier});
        Debug.log(.DEBUG, "\tBibliographic File Identifier:\t{s}", .{self.bibliographicFileIdentifier});
        Debug.log(.DEBUG, "\tVolume Creation Date/Time:\t{s}", .{self.volumeCreationDateTime});
        Debug.log(.DEBUG, "\tVolume Modification Date/Time:\t{s}", .{self.volumeModificationDateTime});
        Debug.log(.DEBUG, "\tVolume Expiration Date/Time:\t{s}", .{self.volumeExpirationDateTime});
        Debug.log(.DEBUG, "\tVolume Effective Date/Time:\t{s}", .{self.volumeEffectiveDateTime});
        Debug.log(.DEBUG, "\tFile Structure Version:\t{d}", .{self.fileStructureVersion});
        Debug.log(.DEBUG, "\tUnused4:\t\t\t0x{x}", .{self.unused4});
        Debug.log(.DEBUG, "\tApplication Used:\t{any}", .{self.applicationUsed});
        Debug.log(.DEBUG, "\tReserved:\t\t{any}", .{self.reserved});
        Debug.log(.DEBUG, "-------------------------------------------------------------------------------\n", .{});
    }

    pub fn printAuto(self: @This()) void {
        inline for (std.meta.fields(@TypeOf(self))) |field| {
            Debug.log(.DEBUG, "\n\t{s}:\t\t\t\t{any}", .{ field.name, @as(field.type, @field(self, field.name)) });

            // switch (@typeInfo(field.type)) {
            //     .Pointer, .Array => Debug.log(.DEBUG, "{s}", @as(field.type, @field(self, field.name))),
            //     .Int => Debug.log(.DEBUG, "{d}", @as(field.type, @field(self, field.name))),
            //     else => Debug.log(.DEBUG, "{any}", @as(field.type, @field(self, field.name))),
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
        Debug.log(.DEBUG, "-------------------------- Boot Record ---------------------------", .{});
        Debug.log(.DEBUG, "\tType Code:\t\t\t{d}", .{self.typeCode});
        Debug.log(.DEBUG, "\tIdentifier:\t\t\t{s}", .{self.standardIdentifier});
        Debug.log(.DEBUG, "\tVersion:\t\t\t{d}", .{self.version});
        Debug.log(.DEBUG, "\tBoot System Identifier:\t\t{s}", .{self.bootSystemIdentifier});
        Debug.log(.DEBUG, "\tBoot Identifier:\t\t{s}", .{self.bootIdentifier});
        Debug.log(.DEBUG, "\tCatalog LBA:\t\t\t{d}\n", .{endian.readLittle(i32, &self.catalogLba)});
        Debug.log(.DEBUG, "-------------------------------------------------------------------------------\n", .{});
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
        Debug.log(.DEBUG, "\n-------------------------- Volume Descriptor Set Terminator ---------------------------", .{});
        Debug.log(.DEBUG, "\tType Code:\t\t\t{d}", .{self.typeCode});
        Debug.log(.DEBUG, "\tIdentifier:\t\t\t{s}", .{self.standardIdentifier});
        Debug.log(.DEBUG, "\tVersion:\t\t\t{d}\n", .{self.version});
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
            Debug.log(.DEBUG, "----------------- Directory Record ---------------------", .{});
            Debug.log(.DEBUG, "\tLength of Dir Record:\t\t\t{d}", .{self.lengthOfDirectoryRecord});
            Debug.log(.DEBUG, "\tLength of Ext Attr Record:\t\t{d}", .{self.lengthOfExtendedAttributeRecord});
            Debug.log(.DEBUG, "\tLocation of Extent:\t\t\t{d}", .{endian.readBoth(i32, &self.locationOfExtent)});
            Debug.log(.DEBUG, "\tData Length:\t\t\t{d}", .{endian.readBoth(i32, &self.dataLength)});
            Debug.log(.DEBUG, "\tFile Flags:\t\t\t{b:0>8}", .{self.fileFlags});
            Debug.log(.DEBUG, "\tLength of File Identifier:\t\t{d}", .{self.lengthOfFileIdentifier});
            Debug.log(.DEBUG, "\tfileIdentifier:\t\t\t{x}\n", .{self.fileIdentifier});
        }
    };
}
