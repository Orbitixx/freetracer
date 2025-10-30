//! Filesystem Utilities Module
//!
//! Provides secure and efficient filesystem operations for both the GUI application
//! and the privileged helper process. This module handles:
//!
//! **Path Management**
//!   - Safe user home directory path construction
//!   - Symlink attack mitigation via path canonicalization
//!   - Buffer overflow prevention on fixed-size stacks
//!   - Whitelist validation (Desktop, Documents, Downloads)
//!
//! **Image File Validation**
//!   - Magic signature detection (ISO 9660, El Torito, MBR, GPT, UDF)
//!   - File extension parsing and classification
//!   - Minimum size validation
//!   - File kind verification (rejects symlinks)
//!
//! **Security Features**
//!   - No symlink following unless explicitly resolved
//!   - Realpath canonicalization for path comparison
//!   - Whitelist-based directory access control
//!   - File descriptor validation
//!
//! This module is critical to the security model - all user-provided file paths
//! must be validated through these functions before use.

const std = @import("std");
const Character = @import("../constants.zig").Character;
const Debug = @import("../util/debug.zig");
const ImageType = @import("../types.zig").ImageType;
const String = @import("../util/string.zig");
const ISOParser = @import("../ISOParser.zig");

/// Supported disk image and partition table formats
pub const FileSystemType = enum {
    ISO9660, // Standard ISO 9660 filesystem
    ISO9660_EL_TORITO, // ISO 9660 with El Torito bootable extension
    MBR, // Master Boot Record partition table
    GPT, // GUID Partition Table (modern alternative to MBR)
    UDF, // Universal Disk Format (used by DVDs/Blu-rays)
    UNKNOWN, // Format not recognized
};

/// Result of image file validation
/// Contains both validity flag and detected filesystem type
pub const ImageFileValidationResult = struct {
    isValid: bool = false,
    fileSystem: FileSystemType = .UNKNOWN,
};

/// Error set for filesystem path operations
pub const PathError = error{
    HomeEnvironmentVariableIsNULL, // $HOME environment variable not set
    PathTooLong, // Constructed path exceeds max_path_bytes
    PathConstructionFailed, // Path format validation failed
};

/// Concatenates the user's home directory path with a relative path segment.
/// Constructs a complete, null-terminated path for use throughout the application.
///
/// `Returns`:
///   Null-terminated slice pointing to the complete path in the buffer
///
/// `Errors`:
///   error.HomeEnvironmentVariableIsNULL: $HOME not set in environment
///   error.PathTooLong: Total path exceeds system maximum
///   error.PathConstructionFailed: restOfPath doesn't start with "/"
///
/// `Example`:
///   var buffer: [std.fs.max_path_bytes]u8 = undefined;
///   const path = try unwrapUserHomePath(&buffer, "/Documents/image.iso");
///   path might be "/Users/{user}/Documents/image.iso"
pub fn unwrapUserHomePath(buffer: *[std.fs.max_path_bytes]u8, restOfPath: []const u8) ![:0]u8 {
    const userDir = std.posix.getenv("HOME") orelse return PathError.HomeEnvironmentVariableIsNULL;

    const totalLen = userDir.len + restOfPath.len;

    // Safety check for buffer overflow and null terminator space.
    if (totalLen >= buffer.len) return PathError.PathTooLong;

    if (restOfPath.len > 0 and restOfPath[0] != Character.RIGHT_SLASH) {
        return PathError.PathConstructionFailed;
    }

    @memcpy(buffer[0..userDir.len], userDir);
    @memcpy(buffer[userDir.len..totalLen], restOfPath);
    buffer[totalLen] = Character.NULL;

    return buffer[0..totalLen :0];
}

/// Validates that a path is within an allowed directory and not a symlink escape.
/// Implements critical security check: prevents access to files outside
/// the whitelisted directories even via symlink tricks.
///
/// Uses realpath() canonicalization to detect and prevent symlink attacks:
/// - Resolves all symlinks and ".." references to canonical form
/// - Compares canonical paths to prevent escaping the whitelist
///
/// Allowed directories (whitelisted):
///   - $HOME/Desktop/
///   - $HOME/Documents/
///   - $HOME/Downloads/
///
/// These directories represent locations where users commonly place ISO images
/// while preventing access to sensitive system files or configuration directories.
///
/// `Arguments`:
///   userHomePath: Absolute path to user home directory (e.g., "/Users/alice")
///                 Usually obtained from unwrapUserHomePath()
///   pathString: File path to validate (e.g., "/Users/alice/Documents/ubuntu.iso")
///               Must be absolute path (starting with "/")
///
/// `Returns`:
///   true if path is within an allowed directory and canonicalization succeeds
///   false if path is outside whitelist or canonicalization fails
///
/// `Security Notes`:
///   - Uses realpath() to resolve all symlinks (prevents symlink attacks)
///   - Validates path length before processing
///   - Returns false on any error (fail-safe)
///   - Symlink to "/etc/passwd" in Desktop returns false (correctly rejected)
pub fn isFilePathAllowed(userHomePath: []const u8, pathString: []const u8) bool {
    if (pathString.len >= std.fs.max_path_bytes) {
        Debug.log(.ERROR, "isFilePathAllowed: Provided path is too long (over std.fs.max_path_bytes).", .{});
        return false;
    }

    // Temporary buffer for canonicalizing the input path (pathString)
    // to compare against canonicalized allowed paths.
    var realInputPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const realInputPath = std.fs.realpath(pathString, &realInputPathBuffer) catch |err| {
        Debug.log(.ERROR, "isFilePathAllowed: Unable to resolve real path of input. Error: {any}", .{err});
        return false;
    };

    const allowedPathsRelative = [_][]const u8{
        "/Desktop/",
        "/Documents/",
        "/Downloads/",
    };

    var allowedPathBuffer: [std.fs.max_path_bytes]u8 = undefined;

    for (allowedPathsRelative) |pathRel| {
        const fullPathLen = userHomePath.len + pathRel.len;

        if (fullPathLen >= std.fs.max_path_bytes) {
            Debug.log(.ERROR, "isFilePathAllowed: Allowed path construction exceeds max_path_bytes.", .{});
            continue;
        }

        // Construct the path (e.g., "/home/user/Desktop/")
        @memcpy(allowedPathBuffer[0..userHomePath.len], userHomePath);
        @memcpy(allowedPathBuffer[userHomePath.len..fullPathLen], pathRel);
        allowedPathBuffer[fullPathLen] = Character.NULL;

        // Canonicalize the constructed allowed directory path.
        var realAllowedPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

        const allowedPathSlice = allowedPathBuffer[0..fullPathLen :0];

        const realAllowedPath = std.fs.realpath(allowedPathSlice, &realAllowedPathBuffer) catch |err| {
            Debug.log(.ERROR, "isFilePathAllowed: Unable to resolve the real path of the allowed path. Error: {any}", .{err});
            continue;
        };

        // Check if the canonicalized input path starts with the canonicalized allowed path.
        // This effectively checks if the input path is inside the allowed directory.
        if (std.mem.startsWith(u8, realInputPath, realAllowedPath)) {
            return true;
        }
    }

    return false;
}

/// Extracts the file extension from a path string.
/// Thin wrapper around std.fs.path.extension() for future compatibility.
/// Includes the leading dot (.) in the result if present.
pub fn getExtensionFromPath(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Checks if ISO 9660 image contains El Torito bootable extension.
/// El Torito is a standard for making ISOs bootable on x86 systems.
/// Looks for boot catalog and validates boot record signatures.
///
/// `Arguments`:
///   file: Open file handle positioned at beginning
///
/// `Returns`:
///   true if valid El Torito boot record found, false otherwise
///
/// `Process`:
///   1. Verify ISO 9660 Primary Volume Descriptor at sector 16
///   2. Read Boot Record Volume Descriptor at sector 16
///   3. Validate "CD001" identifier at bytes 1-5
///   4. Extract boot catalog LBA from bytes 71-74
///   5. Read boot catalog and validate signatures at bytes 0, 30-31
fn isElToritoBootable(file: *const std.fs.File) bool {
    Debug.log(.DEBUG, "isElToritoBootable: Checking for El Torito boot record", .{});
    var buffer: [512]u8 = undefined;

    file.seekTo(0) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to seek to start. Error: {any}", .{err});
        return false;
    };

    const bytes_read = file.read(&buffer) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to read file. Error: {any}", .{err});
        return false;
    };

    if (bytes_read < 512) {
        Debug.log(.DEBUG, "isElToritoBootable: File too small to read sector", .{});
        return false;
    }

    if (!isISO9660(buffer)) {
        return false;
    }

    var catalog_lba_buffer: [512]u8 = undefined;

    file.seekTo(32768) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to seek to sector 16. Error: {any}", .{err});
        return false;
    };

    const catalog_bytes = file.read(&catalog_lba_buffer) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to read sector 16. Error: {any}", .{err});
        return false;
    };

    if (catalog_bytes < 512) {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to read full sector", .{});
        return false;
    }

    if (catalog_lba_buffer[0] != 0x00) {
        Debug.log(.DEBUG, "isElToritoBootable: Sector 16 is not boot record (type code: 0x{x})", .{catalog_lba_buffer[0]});
        return false;
    }

    const boot_id_slice = catalog_lba_buffer[1..6];
    if (!std.mem.eql(u8, boot_id_slice, "CD001")) {
        Debug.log(.DEBUG, "isElToritoBootable: Boot record lacks proper identifier", .{});
        return false;
    }

    const catalog_lba_offset: u32 = @bitCast([4]u8{
        catalog_lba_buffer[71],
        catalog_lba_buffer[72],
        catalog_lba_buffer[73],
        catalog_lba_buffer[74],
    });

    file.seekTo(catalog_lba_offset * 2048) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to seek to boot catalog. Error: {any}", .{err});
        return false;
    };

    const boot_cat_bytes = file.read(&buffer) catch |err| {
        Debug.log(.DEBUG, "isElToritoBootable: Unable to read boot catalog. Error: {any}", .{err});
        return false;
    };

    if (boot_cat_bytes < 32) {
        Debug.log(.DEBUG, "isElToritoBootable: Boot catalog sector too small", .{});
        return false;
    }

    if (buffer[0] != 0x01) {
        Debug.log(.DEBUG, "isElToritoBootable: Boot catalog validation entry header invalid (0x{x})", .{buffer[0]});
        return false;
    }

    if (buffer[30] == 0x55 and buffer[31] == 0xAA) {
        Debug.log(.DEBUG, "isElToritoBootable: Found valid El Torito boot catalog signature", .{});
        return true;
    }

    Debug.log(.DEBUG, "isElToritoBootable: Boot catalog signature not found", .{});
    return false;
}

/// Checks if file contains UDF (Universal Disk Format) signatures.
/// UDF is used by DVDs, Blu-rays, and some USB devices.
/// Multiple signature types indicate UDF presence at different locations.
///
/// `Arguments`:
///   file: Open file handle positioned at beginning
///
/// `Returns`:
///   true if UDF descriptors found, false otherwise
///
/// `UDF Signature Detection`:
///   - Checks VSD at offset 256 bytes for "BEA01", "NSR02", "NSR03"
///   - Falls back to sector 16 (offset 32768) if not found
///   - Validates minimum file size (32 sectors = 64KB)
fn isUDF(file: *const std.fs.File) bool {
    Debug.log(.DEBUG, "isUDF: Checking for UDF signatures", .{});
    var buffer: [512]u8 = undefined;

    const file_stat = file.stat() catch |err| {
        Debug.log(.DEBUG, "isUDF: Unable to stat file. Error: {any}", .{err});
        return false;
    };

    if (file_stat.size < 32 * 2048) {
        Debug.log(.DEBUG, "isUDF: File too small for UDF (minimum 32 sectors)", .{});
        return false;
    }

    file.seekTo(256) catch |err| {
        Debug.log(.DEBUG, "isUDF: Unable to seek to byte 256. Error: {any}", .{err});
        return false;
    };

    const bytes_read = file.read(&buffer) catch |err| {
        Debug.log(.DEBUG, "isUDF: Unable to read at offset 256. Error: {any}", .{err});
        return false;
    };

    if (bytes_read < 512) {
        Debug.log(.DEBUG, "isUDF: Insufficient bytes read", .{});
        return false;
    }

    const vsd_ident_slice = buffer[1..6];
    if (std.mem.eql(u8, vsd_ident_slice, "CD001")) {
        Debug.log(.DEBUG, "isUDF: Found ISO 9660 VSD, not pure UDF", .{});
        return false;
    }

    if (std.mem.eql(u8, vsd_ident_slice, "BEA01")) {
        Debug.log(.DEBUG, "isUDF: Found UDF Beginning Extended Area Descriptor", .{});
        return true;
    }

    if (std.mem.eql(u8, vsd_ident_slice, "NSR02") or std.mem.eql(u8, vsd_ident_slice, "NSR03")) {
        Debug.log(.DEBUG, "isUDF: Found UDF Namespace descriptor (version 2 or 3)", .{});
        return true;
    }

    file.seekTo(32768) catch |err| {
        Debug.log(.DEBUG, "isUDF: Unable to seek to sector 16. Error: {any}", .{err});
        return false;
    };

    const sector16_bytes = file.read(&buffer) catch |err| {
        Debug.log(.DEBUG, "isUDF: Unable to read sector 16. Error: {any}", .{err});
        return false;
    };

    if (sector16_bytes < 512) {
        Debug.log(.DEBUG, "isUDF: Unable to read full sector 16", .{});
        return false;
    }

    const sector16_ident = buffer[1..6];
    if (std.mem.eql(u8, sector16_ident, "BEA01") or
        std.mem.eql(u8, sector16_ident, "NSR02") or
        std.mem.eql(u8, sector16_ident, "NSR03"))
    {
        Debug.log(.DEBUG, "isUDF: Found UDF descriptor at sector 16", .{});
        return true;
    }

    Debug.log(.DEBUG, "isUDF: No UDF signatures found", .{});
    return false;
}

/// Detects ISO 9660 filesystem signature.
/// ISO 9660 (also called CDFS) is the standard format for CDs and DVDs.
/// The signature "CD001" appears at bytes 1-5 of sector 16 (offset 32768).
///
/// `Arguments`:
///   buffer: 512-byte sector buffer (typically sector 16)
///
/// `Returns`:
///   true if "CD001" signature found at correct offset
///
/// `Technical Details`:
///   - Primary Volume Descriptor located at LBA 16
///   - Signature bytes 1-5: "CD001"
///   - This is the most reliable way to detect ISO 9660 images
fn isISO9660(buffer: [512]u8) bool {
    if (buffer.len < 512) return false;

    const expected_signature = "CD001";

    if (buffer.len >= 6) {
        if (std.mem.eql(u8, buffer[1..6], expected_signature)) {
            return true;
        }
    }

    return false;
}

/// Detects MBR (Master Boot Record) partition table signature.
/// MBR is the legacy partition table format for BIOS systems.
/// The boot signature 0x55 0xAA appears at the end of sector 0.
///
/// `Arguments`:
///   buffer: 512-byte MBR sector buffer
///
/// `Returns`:
///   true if MBR boot signature found at bytes 510-511
///
/// `Technical Details`:
///   - Located at sector 0 (first sector)
///   - Boot signature: 0x55AA at bytes 510-511
///   - This is also called "partition table signature"
fn isMBRPartitionTable(buffer: [512]u8) bool {
    if (buffer.len < 512) return false;

    const mbr_signature_1 = buffer[510];
    const mbr_signature_2 = buffer[511];

    return mbr_signature_1 == 0x55 and mbr_signature_2 == 0xAA;
}

/// Detects GPT (GUID Partition Table) signature.
/// GPT is the modern partition table format for UEFI systems.
/// The signature "EFI PART" appears at the start of sector 1 (LBA 1).
///
/// `Arguments`:
///   file: Open file handle positioned at beginning
///
/// `Returns`:
///   true if GPT header signature found at LBA 1
///
/// `Technical Details`:
///   - GPT header located at LBA 1 (sector 1, offset 512)
///   - Signature: "EFI PART" (8 bytes at offset 0)
///   - Modern replacement for MBR on UEFI systems
///   - Requires file seek capability
fn isGPTPartitionTable(file: *const std.fs.File) bool {
    Debug.log(.DEBUG, "isGPTPartitionTable: Starting GPT check", .{});
    var buffer: [512]u8 = undefined;

    Debug.log(.DEBUG, "isGPTPartitionTable: Seeking to LBA 1 (offset 512)", .{});
    file.seekTo(512) catch |err| {
        Debug.log(.DEBUG, "isGPTPartitionTable: Unable to seek to LBA 1. Error: {any}", .{err});
        return false;
    };

    Debug.log(.DEBUG, "isGPTPartitionTable: Reading LBA 1", .{});
    const bytes_read = file.read(&buffer) catch |err| {
        Debug.log(.DEBUG, "isGPTPartitionTable: Unable to read LBA 1. Error: {any}", .{err});
        return false;
    };

    Debug.log(.DEBUG, "isGPTPartitionTable: Read {d} bytes from LBA 1", .{bytes_read});

    if (bytes_read < 8) {
        Debug.log(.DEBUG, "isGPTPartitionTable: Not enough bytes read", .{});
        return false;
    }

    const gpt_signature = "EFI PART";
    if (std.mem.eql(u8, buffer[0..8], gpt_signature)) {
        Debug.log(.DEBUG, "isGPTPartitionTable: Found GPT signature", .{});
        return true;
    }

    Debug.log(.DEBUG, "isGPTPartitionTable: No GPT signature found", .{});
    return false;
}

/// Validates that a file contains recognized disk image magic signatures.
/// Checks for multiple image format types in order of likelihood.
/// This is the primary validation function for determining if a file is a valid image.
///
/// `Arguments`:
///   file: Open file handle (caller responsible for opening with read permissions)
///
/// `Returns`:
///   ImageFileValidationResult containing:
///     - isValid: true if recognized signature found
///     - fileSystem: Type of image detected (ISO9660, MBR, GPT, UDF, etc.)
///
/// `Validation Process`:
///   1. Check minimum file size (512 bytes for first sector)
///   2. Check ISO 9660 signature (most common)
///   3. Check for El Torito bootable extension (within ISO 9660)
///   4. Check UDF signatures (DVDs, Blu-rays)
///   5. Check MBR partition table signature
///   6. Check GPT partition table signature
///
/// `Supported Formats`:
///   - ISO9660: Standard CD/DVD image format
///   - ISO9660_EL_TORITO: ISO with bootable extension
///   - UDF: DVD/Blu-ray disc format
///   - MBR: Master Boot Record partition table
///   - GPT: GUID Partition Table (modern alternative)
///
/// `Security`:
///   - File must be opened by caller with appropriate permissions
///   - Validates file size before reading
///   - Returns invalid result on any I/O errors
pub fn validateImageFile(file: std.fs.File) ImageFileValidationResult {
    Debug.log(.DEBUG, "isValidImageFile: Starting validation", .{});
    var buffer: [512]u8 = undefined;
    const badResult = ImageFileValidationResult{};

    const stat = file.stat() catch |err| {
        Debug.log(.ERROR, "isValidImageFile: Unable to obtain file stat. Error: {any}", .{err});
        return badResult;
    };

    if (stat.size < 512) {
        Debug.log(.ERROR, "isValidImageFile: File is too small to contain valid image signatures.", .{});
        return badResult;
    }

    Debug.log(.DEBUG, "isValidImageFile: Seeking to start of file", .{});
    file.seekTo(0) catch |err| {
        Debug.log(.ERROR, "isValidImageFile: Unable to seek to beginning of file. Error: {any}", .{err});
        return badResult;
    };

    Debug.log(.DEBUG, "isValidImageFile: Reading first 512 bytes", .{});
    const bytes_read = file.read(&buffer) catch |err| {
        Debug.log(.ERROR, "isValidImageFile: Unable to read file. Error: {any}", .{err});
        return badResult;
    };

    Debug.log(.DEBUG, "isValidImageFile: Read {d} bytes", .{bytes_read});

    if (bytes_read < 512) {
        Debug.log(.ERROR, "isValidImageFile: Unable to read full 512 byte sector.", .{});
        return badResult;
    }

    if (isISO9660(buffer)) {
        Debug.log(.DEBUG, "isValidImageFile: Detected ISO 9660 image.", .{});
        if (isElToritoBootable(&file)) {
            Debug.log(.DEBUG, "isValidImageFile: ISO contains El Torito boot catalog.", .{});
            return .{ .isValid = true, .fileSystem = .ISO9660_EL_TORITO };
        }
        return .{ .isValid = true, .fileSystem = .ISO9660 };
    }

    Debug.log(.DEBUG, "isValidImageFile: Checking for UDF", .{});
    if (isUDF(&file)) {
        Debug.log(.DEBUG, "isValidImageFile: Detected UDF filesystem.", .{});
        return .{ .isValid = true, .fileSystem = .UDF };
    }

    if (isMBRPartitionTable(buffer)) {
        Debug.log(.DEBUG, "isValidImageFile: Detected MBR partition table.", .{});
        return .{ .isValid = true, .fileSystem = .MBR };
    }

    Debug.log(.DEBUG, "isValidImageFile: Checking for GPT partition table", .{});
    if (isGPTPartitionTable(&file)) {
        Debug.log(.DEBUG, "isValidImageFile: Detected GPT partition table.", .{});
        return .{ .isValid = true, .fileSystem = .GPT };
    }

    Debug.log(.WARNING, "isValidImageFile: File does not contain recognized image signatures.", .{});
    return badResult;
}

/// Classifies image type based on file extension.
/// Performs case-insensitive extension matching.
/// Used to provide user-facing information about the image file.
///
/// `Arguments`:
///   path: File path (any format, just used for extension extraction)
///
/// `Returns`:
///   ImageType.ISO if extension is .iso (case-insensitive)
///   ImageType.IMG if extension is .img (case-insensitive)
///   ImageType.Other for any other extension
///
/// `Note`:
///   This is purely a hint based on file extension, not validation.
///   Always call validateImageFile() for actual format verification.
pub fn getImageType(path: []const u8) ImageType {
    const ext = getExtensionFromPath(path);

    if (std.ascii.eqlIgnoreCase(ext, ".ISO")) return .ISO;
    if (std.ascii.eqlIgnoreCase(ext, ".IMG")) return .IMG;

    return .Other;
}

// ============================================================================
// FILE OPENING - Open and validate image files with security checks
// ============================================================================

/// Opens an ISO image file with comprehensive security validation.
/// This is the primary entry point for accessing user-provided image files.
/// Implements defense-in-depth with multiple validation layers.
///
/// `Validation Steps`:
///   1. Path length check (prevent buffer overflow)
///   2. Home path validation
///   3. Real path resolution (symlink canonicalization)
///   4. Path length validation (min 8 chars)
///   5. Whitelist check (must be in Desktop/Documents/Downloads)
///   6. Directory opening with no_follow flag
///   7. File opening with read_only mode
///   8. File stat validation
///   9. File kind check (must be regular file, reject symlinks)
///   10. Minimum size check (must be at least 17 sectors = 34816 bytes)
///
/// `Arguments`:
///   unsanitizedIsoPath: User-provided path (NOT trusted, requires validation)
///   params.userHomePath: User home directory (must be provided securely)
///
/// `Returns`:
///   Open std.fs.File handle for reading the image
///   Caller responsible for closing the file
///
/// `Errors`:
///   error.ISOFilePathTooLong: Path exceeds system maximum
///   error.UserHomePathTooShort: Invalid home path
///   error.UnableToResolveRealISOPath: Path resolution failed
///   error.ISOFilePathTooShort: Path too short to be valid
///   error.ISOFileContainsRestrictedPaths: Outside whitelist
///   error.UnableToOpenDirectoryOfSpecificedISOFile: Directory access failed
///   error.UnableToOpenISOFileOrObtainExclusiveLock: File open failed
///   error.UnableToObtainISOFileStat: File stat failed
///   error.InvalidISOFileKind: Not a regular file (e.g., symlink, directory)
///   error.InvalidISOSystemStructure: File too small for valid ISO
///
/// `Security Features`:
///   - Realpath resolves all symlinks (prevents symlink escape)
///   - no_follow flag on directory open prevents symlink races
///   - File kind validation rejects symlinks
///   - Whitelist prevents access to system directories
///   - Minimum size check for basic sanity
pub fn openFileValidated(unsanitizedIsoPath: []const u8, params: struct { userHomePath: []const u8 }) !std.fs.File {
    Debug.log(.DEBUG, "openFileValidated: Starting validation for path", .{});

    // Buffer overflow protection
    if (unsanitizedIsoPath.len > std.fs.max_path_bytes) {
        Debug.log(.ERROR, "openFileValidated: Provided path is too long (over std.fs.max_path_bytes).", .{});
        return error.ISOFilePathTooLong;
    }

    if (params.userHomePath.len < 3) return error.UserHomePathTooShort;

    var realPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    var sanitizeStringBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    Debug.log(.DEBUG, "openFileValidated: Attempting to resolve real path", .{});
    const imagePath = std.fs.realpath(unsanitizedIsoPath, &realPathBuffer) catch |err| {
        Debug.log(.ERROR, "openFileValidated: Unable to resolve the real path of the povided path: {s}. Error: {any}", .{
            String.sanitizeString(&sanitizeStringBuffer, unsanitizedIsoPath),
            err,
        });
        return error.UnableToResolveRealISOPath;
    };

    Debug.log(.DEBUG, "openFileValidated: Real path resolved successfully", .{});
    const printableIsoPath = String.sanitizeString(&sanitizeStringBuffer, imagePath);

    if (imagePath.len < 8) {
        Debug.log(.ERROR, "openFileValidated: Provided path is less than 8 characters long. Likely invalid, aborting for safety...", .{});
        return error.ISOFilePathTooShort;
    }

    const directory = std.fs.path.dirname(imagePath) orelse ".";
    const fileName = std.fs.path.basename(imagePath);

    Debug.log(.DEBUG, "openFileValidated: Checking if path is allowed", .{});
    if (!isFilePathAllowed(params.userHomePath, directory)) {
        Debug.log(.ERROR, "openFileValidated: Provided path contains a disallowed part: {s}", .{printableIsoPath});
        return error.ISOFileContainsRestrictedPaths;
    }

    Debug.log(.DEBUG, "openFileValidated: Opening directory", .{});
    const dir = std.fs.openDirAbsolute(directory, .{ .no_follow = true }) catch |err| {
        Debug.log(.ERROR, "openFileValidated: Unable to open the directory of specified ISO file. Aborting... Error: {any}", .{err});
        return error.UnableToOpenDirectoryOfSpecificedISOFile;
    };

    Debug.log(.DEBUG, "openFileValidated: Opening file without lock first", .{});
    const imageFile = dir.openFile(fileName, .{ .mode = .read_only, .lock = .none }) catch |err| {
        Debug.log(.ERROR, "openFileValidated: Failed to open ISO file. Error: {any}", .{err});
        return error.UnableToOpenISOFileOrObtainExclusiveLock;
    };

    Debug.log(.DEBUG, "openFileValidated: Getting file statistics", .{});
    const fileStat = imageFile.stat() catch |err| {
        Debug.log(.ERROR, "openFileValidated: Failed to obtain ISO file stat. Error: {any}", .{err});
        return error.UnableToObtainISOFileStat;
    };

    Debug.log(.DEBUG, "openFileValidated: File size is {d} bytes", .{fileStat.size});

    if (fileStat.kind != std.fs.File.Kind.file) {
        Debug.log(
            .ERROR,
            "openFileValidated: The provided ISO path is not a recognized file by file system. Symlinks and other kinds are not allowed. Kind used: {any}",
            .{fileStat.kind},
        );
        return error.InvalidISOFileKind;
    }

    // Minimum ISO system block: 16 sectors by 2048 bytes each + 1 sector for PVD contents.
    if (fileStat.size < (16 + 1) * 2048) {
        Debug.log(.ERROR, "openFileValidated: File size {d} is smaller than minimum required {d}", .{ fileStat.size, (16 + 1) * 2048 });
        return error.InvalidISOSystemStructure;
    }

    Debug.log(.DEBUG, "openFileValidated: All validations passed, returning file handle", .{});

    return imageFile;
}

/// Validates internal structure of ISO 9660 images.
/// Performs deep validation of ISO filesystem headers and structure.
/// Called after magic signature detection for comprehensive validation.
///
/// `Arguments`:
///   imageType: Detected filesystem type from validateImageFile()
///   imageFile: Open file handle to the image
///
/// `Current Behavior`:
///   - Only validates ISO9660 type (other types skipped)
///   - Calls ISOParser.validateISOFileStructure()
///   - Returns error on structural violations
///
/// `TODO`:
///   - Add user prompt for invalid ISO structures
///   - Consider allowing user to proceed with invalid ISO
pub fn validateISOStructure(imageType: FileSystemType, imageFile: std.fs.File) void {
    if (imageType == .ISO9660) {
        const isoValidationResult = ISOParser.validateISOFileStructure(imageFile);

        // TODO: If ISO structure does not conform to ISO9660, prompt user to proceed or not.
        if (isoValidationResult != .ISO_VALID) {
            Debug.log(.ERROR, "Invalid ISO file structure detected. Aborting... Error code: {any}", .{isoValidationResult});
            return error.InvalidISOStructureDoesNotConformToISO9660;
        }
    }
}

// --- Unit Tests ---
test "unwrapUserHomePath tests" {

    // Test standard concatenation
    {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const rest_of_path = "/project/file.txt";
        const result = try unwrapUserHomePath(&buffer, rest_of_path);

        const expected = "/tmp/mock_user/project/file.txt";
        try std.testing.expectEqualStrings(expected, result);
        try std.testing.expectEqual(buffer[result.len], @as(u8, Character.NULL)); // Check for null terminator
    }

    // Test concatenation with a bare subdirectory
    {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const rest_of_path = "/Downloads";
        const result = try unwrapUserHomePath(&buffer, rest_of_path);

        const expected = "/tmp/mock_user/Downloads";
        try std.testing.expectEqualStrings(expected, result);
    }

    // Home path is exactly max_path_bytes long (should fail due to null terminator)
    {
        var big_home_path_bytes: [std.fs.max_path_bytes]u8 = [_]u8{'a'} ** std.fs.max_path_bytes;
        const big_home_path = big_home_path_bytes[0..std.fs.max_path_bytes];
        var buffer: [std.fs.max_path_bytes]u8 = undefined;

        // This MUST return .PathTooLong because the total length (len + null byte) exceeds max_path_bytes
        try std.testing.expectError(PathError.PathTooLong, unwrapUserHomePath(&buffer, big_home_path));
    }
}

test "isFilePathAllowed tests" {
    // Note: To test realpath accurately, we must ensure the mock paths exist.
    // For this test, we will create temporary directories.

    const buffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const home = unwrapUserHomePath(&buffer, "");

    const home_path_slice = std.mem.sliceTo(home, Character.NULL);

    // 1. Test allowed file path (simple)
    try std.testing.expect(isFilePathAllowed(home_path_slice, home ++ "/Desktop/report.pdf"));

    // 2. Test allowed directory path (exact match of allowed prefix)
    try std.testing.expect(isFilePathAllowed(home_path_slice, home ++ "/Downloads/"));

    // 3. Test disallowed file path
    try std.testing.expectEqual(false, isFilePathAllowed(home_path_slice, home ++ "/Forbidden/secret.key"));

    // 4. Test path outside home directory
    try std.testing.expectEqual(false, isFilePathAllowed(home_path_slice, "/etc/passwd"));

    // 5. Test against relative path (should fail as realpath expects an absolute path on most systems)
    try std.testing.expectEqual(false, isFilePathAllowed(home_path_slice, "Desktop/report.pdf"));

    // 6. Test with path traversal (symlink attack mitigation) - this verifies realpath logic
    // We create a symlink in an allowed directory pointing outside.
    const link_name = "secret_link";
    const link_path = home ++ "/Desktop/" ++ link_name;
    const target_path = "/etc/passwd";

    std.fs.symLinkAbsolute(target_path, link_path, .{}) catch |err| {
        std.log.warn("Skipping symlink test due to error: {any}", .{err});
        return;
    };

    // The input path is the path *with* the symlink
    const symlinked_input = link_path;

    // Because isFilePathAllowed canonicalizes the *input* path first,
    // it will resolve to `/etc/passwd`.
    // It then checks if `/etc/passwd` starts with `/tmp/mock_user/Desktop/`.
    // This should fail, which is the correct security behaviour.
    try std.testing.expectEqual(false, isFilePathAllowed(home_path_slice, symlinked_input));

    // 7. Test long path string (should fail early)
    var long_path_str: [std.fs.max_path_bytes + 10]u8 = std.mem.zeroes([std.fs.max_path_bytes + 10]u8);
    @memset(long_path_str[0..], 'x');
    long_path_str[std.fs.max_path_bytes + 10] = Character.NULL;
    try std.testing.expectEqual(false, isFilePathAllowed(home_path_slice, long_path_str[0..]));
}

test "getExtensionFromPath: full path with extension" {
    const path = "/home/user/files/photo.JPG";
    const expected = ".JPG";
    try std.testing.expectEqualStrings(expected, getExtensionFromPath(path));
}

test "getExtensionFromPath: hidden file" {
    const path = ".config";
    // `std.fs.path.extension` considers the whole name to be the stem for dotfiles.
    const expected = "";
    try std.testing.expectEqualStrings(expected, getExtensionFromPath(path));
}

test "getExtensionFromPath: file with no extension" {
    const path = "/usr/bin/zig";
    const expected = "";
    try std.testing.expectEqualStrings(expected, getExtensionFromPath(path));
}

test "validateImageFile: ISO 9660 detection" {
    const USER_HOME_PATH = "/Users/cerberus";
    const TEST_ISO_FILE_PATH = "/Documents/Projects/freetracer/tinycore.iso";

    const imageFile = std.fs.openFileAbsolute(USER_HOME_PATH ++ TEST_ISO_FILE_PATH, .{ .mode = .read_only }) catch |err| {
        std.debug.print("Skipping ISO detection test: {any}\n", .{err});
        return;
    };
    defer imageFile.close();

    try std.testing.expect(validateImageFile(imageFile).isValid);
}

test "getImageType: lowercase .iso file" {
    const path = "ubuntu-desktop.iso";
    try std.testing.expect(getImageType(path) == .ISO);
}

test "getImageType: mixed case .iso file" {
    const path = "Windows.IsO";
    try std.testing.expect(getImageType(path) == .ISO);
}

test "getImageType: uppercase .img file" {
    const path = "/mnt/images/RASPBIAN.IMG";
    try std.testing.expect(getImageType(path) == .IMG);
}

test "getImageType: other extension returns .Other" {
    const path = "data.zip";
    try std.testing.expect(getImageType(path) == .Other);
}

test "getImageType: path with no extension returns .Other" {
    const path = "firmware_image";
    try std.testing.expect(getImageType(path) == .Other);
}

test "calling openFileValidated returns a valid file handle" {
    const USER_HOME_PATH = "/Users/cerberus";
    const TEST_ISO_FILE_PATH = "/Documents/Projects/freetracer/tinycore.iso";

    const imageFile = try openFileValidated(
        // Simulated; during runtime, provided by the XPC client.
        USER_HOME_PATH ++ TEST_ISO_FILE_PATH,
        // Simulated; during runtime, provided securily by XPCService.getUserHomePath()
        .{ .userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL },
    );

    defer imageFile.close();

    try std.testing.expect(@TypeOf(imageFile) == std.fs.File);
}
