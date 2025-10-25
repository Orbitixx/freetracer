// Filesystem utilities shared between the GUI client and helper for
// constructing safe user paths, whitelisting image locations, and inspecting
// path metadata such as extensions and image types.
// All helpers here avoid following symlinks unless explicitly resolved and
// guard against buffer overflows on fixed-size stacks.
// -------------------------------------------------------------------------------
const std = @import("std");
const Character = @import("../constants.zig").Character;
const Debug = @import("../util/debug.zig");
const ImageType = @import("../types.zig").ImageType;
const String = @import("../util/string.zig");
const ISOParser = @import("../ISOParser.zig");

pub const FileSystemType = enum {
    ISO9660,
    MBR,
    GPT,
    UNKNOWN,
};

pub const ImageFileValidationResult = struct {
    isValid: bool = false,
    fileSystem: FileSystemType = .UNKNOWN,
};

/// Error set for path operations.
pub const PathError = error{
    HomeEnvironmentVariableIsNULL,
    PathTooLong,
    PathConstructionFailed,
};

/// Concatenates the user's home directory path (retrieved from $HOME) with
/// a provided relative path segment, storing the result in the given buffer.
///
/// The function assumes that the `restOfPath` *begins* with the necessary
/// path separator (`/`).
///
/// Parameters:
///   - buffer: A pointer to a fixed-size buffer (`[std.fs.max_path_bytes]u8`)
///             where the resulting path string will be written.
///   - restOfPath: The segment of the path to append (e.g., "/Documents/file.txt").
///
/// Returns `![:0]u8`
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

/// Checks if a given `pathString` is a descendant of one of the allowed directories
/// within the user's home path. This function performs canonicalization (using
/// `std.fs.realpath`) on the allowed paths to mitigate symlink attacks.
///
/// The allowed directories are:
///   - "{userHomePath}/Desktop/"
///   - "{userHomePath}/Documents/"
///   - "{userHomePath}/Downloads/"
///
/// Parameters:
///   - userHomePath: The absolute path to the user's home directory (e.g., "/home/user").
///                   This is typically retrieved from `unwrapUserHomePath`.
///   - pathString: The absolute path string provided by the user to be checked.
///
/// Returns: `bool`
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

/// Extracts the file extension from a given path slice.
/// This is a wrapper around `std.fs.path.extension`, anticipating potential std changes in the future.
/// The returned slice includes the leading dot ('.') if an extension exists.
/// If no extension is found, an empty slice is returned.
///
/// For example:
/// "/path/to/file.txt" -> ".txt"
/// "/path/to/archive.tar.gz" -> ".gz"
/// "/path/to/file" -> ""
pub fn getExtensionFromPath(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Checks whether a file handle points to a valid disk image.
/// This function checks for ISO 9660, MBR, or GPT signatures only.
/// The caller is responsible for opening the file with appropriate flags.
///
/// Parameters:
///   - `file`: An open std.fs.File handle pointing to the image file.
///
/// Returns: `bool`
/// - `true` if the file contains a recognized magic signature (ISO 9660, MBR, or GPT)
/// - `false` if the file is too small, unreadable, or does not contain a recognized signature
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
        return .{ .isValid = true, .fileSystem = .ISO9660 };
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

/// Checks for ISO 9660 magic signature.
/// ISO 9660 has a Primary Volume Descriptor at sector 16 (offset 32KB).
/// The signature is the string "CD001" at bytes 1-5 of that sector.
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

/// Checks for MBR partition table magic signature.
/// MBR has the boot signature 0x55 0xAA at bytes 510-511.
fn isMBRPartitionTable(buffer: [512]u8) bool {
    if (buffer.len < 512) return false;

    const mbr_signature_1 = buffer[510];
    const mbr_signature_2 = buffer[511];

    return mbr_signature_1 == 0x55 and mbr_signature_2 == 0xAA;
}

/// Checks for GPT partition table magic signature.
/// GPT has the signature "EFI PART" at offset 0 on LBA 1 (512 bytes after MBR).
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

/// Determines the `ImageType` enum based on the file path's extension.
/// This function performs a case-insensitive check for `.ISO` and `.IMG`.
/// If the extension does not match either of those, it defaults to `ImageType.Other`.
///
/// Returns `ImageType`
pub fn getImageType(path: []const u8) ImageType {
    const ext = getExtensionFromPath(path);

    if (std.ascii.eqlIgnoreCase(ext, ".ISO")) return .ISO;
    if (std.ascii.eqlIgnoreCase(ext, ".IMG")) return .IMG;

    return .Other;
}

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
//

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
