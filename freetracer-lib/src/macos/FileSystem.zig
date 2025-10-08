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

/// Checks if a file path's extension is present within a given array of allowed extensions.
/// The comparison is performed case-insensitively.
///
/// Parameters:
///   - `n`: (Comptime) The size of the `allowedExtensionsArray`.
///   - `allowedExtensionsArray`: An array of string literals representing valid extensions (e.g., `.{".iso", ".img"}`).
///   - `path`: The full file path to check.
///
/// Returns `true` if the path's extension is in the allowed list, `false` otherwise.
pub fn isExtensionAllowed(comptime n: usize, allowedExtensionsArray: [n][]const u8, path: []const u8) bool {
    const ext: []const u8 = getExtensionFromPath(path);

    if (ext.len == 0) return false;

    for (allowedExtensionsArray) |allowedExt| if (std.ascii.eqlIgnoreCase(ext, allowedExt)) return true;

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

test "isExtensionAllowed: allowed extension is present and matches case" {
    const allowed = [_][]const u8{ ".log", ".txt" };
    const path = "info.log";
    try std.testing.expect(isExtensionAllowed(allowed.len, allowed, path));
}

test "isExtensionAllowed: allowed extension is present with different case" {
    const allowed = [_][]const u8{ ".log", ".txt" };
    const path = "/var/log/system.LOG";
    try std.testing.expect(isExtensionAllowed(allowed.len, allowed, path));
}

test "isExtensionAllowed: disallowed extension" {
    const allowed = [_][]const u8{ ".jpg", ".png" };
    const path = "document.pdf";
    try std.testing.expect(!isExtensionAllowed(allowed.len, allowed, path));
}

test "isExtensionAllowed: path has no extension" {
    const allowed = [_][]const u8{ ".iso", ".img" };
    const path = "my-iso-image";
    try std.testing.expect(!isExtensionAllowed(allowed.len, allowed, path));
}

test "isExtensionAllowed: empty allowed list" {
    const allowed = [_][]const u8{};
    const path = "file.txt";
    try std.testing.expect(!isExtensionAllowed(allowed.len, allowed, path));
}

test "isExtensionAllowed: file with multiple dots" {
    const allowed = [_][]const u8{ ".gz", ".zip" };
    const path = "backup.tar.gz";
    try std.testing.expect(isExtensionAllowed(allowed.len, allowed, path));
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
