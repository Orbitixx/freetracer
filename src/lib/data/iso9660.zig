const std = @import("std");
const eltorito = @import("eltorito.zig");
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
        debug.printf("\n\tSystem Identifier:\t\t{s}", .{self.systemIdentifier});
        debug.printf("\n\tVolume Identifier:\t\t{s}", .{self.volumeIdentifier});
        debug.printf("\n\tVolume Space Size:\t\t{any}", .{self.volumeSpaceSize});
        debug.printf("\n\tVolume Set Size:\t\t{any}", .{self.volumeSetSize});
        debug.printf("\n\tVolume Sequence Number:\t{any}", .{self.volumeSequenceNumber});
        debug.printf("\n\tLogical Block Size:\t{any}", .{self.logicalBlockSize});
        debug.printf("\n\tPath Table Size:\t\t{any}", .{self.pathTableSize});
        debug.printf("\n\tLocation of Type-L Path Table:\t{any}", .{self.locationOfTypeLPathTable});
        debug.printf("\n\tLocation of Optional Type-L Path Table:\t{any}", .{self.locationOfOptionalTypeLPathTable});
        debug.printf("\n\tLocation of Type-M Path Table:\t{any}", .{self.locationOfTypeMPathTable});
        debug.printf("\n\tLocation of Optional Type-M Path Table:\t{any}", .{self.locationOfOptionalTypeMPathTable});
        debug.printf("\n\tVolume Set Identifier:\t{s}", .{self.volumeSetIdentifier});
        debug.printf("\n\tPublisher Identifier:\t{s}", .{self.publisherIdentifier});
        debug.printf("\n\tData Preparer Identifier:\t{s}", .{self.dataPreparerIdentifier});
        debug.printf("\n\tApplication Identifier:\t{s}", .{self.applicationIdentifier});
        debug.printf("\n\tFile Structure Version:\t{d}", .{self.fileStructureVersion});
        debug.print("\n-------------------------------------------------------------------------------\n");
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
        debug.printf("\n\tCatalog LBA:\t\t\t{d}\n", .{std.mem.readInt(i32, &self.catalogLba, std.builtin.Endian.little)});
        debug.print("\n-------------------------------------------------------------------------------\n");
    }
};

pub const BootCatalog = struct {
    validationEntry: eltorito.ValidationEntry, // 32b
    initialDefaultEntry: eltorito.InitialDefaultEntry, // 32b

    // Optional sector head and entries
    // https://dev.lovelyhq.com/libburnia/libisofs/raw/branch/master/doc/boot_sectors.txt
    optional: [1984]u8,
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
