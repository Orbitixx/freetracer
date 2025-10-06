const std = @import("std");
const Character = @import("../constants.zig").Character;
const Debug = @import("../util/debug.zig");
const ImageType = @import("../types.zig").ImageType;

pub fn unwrapUserHomePath(buffer: *[std.fs.max_path_bytes]u8, restOfPath: []const u8) ![]u8 {
    const userDir = std.posix.getenv("HOME") orelse return error.HomeEnvironmentVariableIsNULL;

    @memcpy(buffer[0..userDir.len], userDir);
    @memcpy(buffer[userDir.len .. userDir.len + restOfPath.len], restOfPath);

    return buffer[0 .. userDir.len + restOfPath.len];
}

pub fn isFilePathAllowed(userHomePath: []const u8, pathString: []const u8) bool {
    var realPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    const allowedPathsRelative = [_][]u8{
        @ptrCast(@constCast("/Desktop/")),
        @ptrCast(@constCast("/Documents/")),
        @ptrCast(@constCast("/Downloads/")),
    };

    var allowedPaths = std.mem.zeroes([allowedPathsRelative.len][std.fs.max_path_bytes]u8);

    for (allowedPathsRelative, 0..allowedPathsRelative.len) |pathRel, i| {
        @memcpy(allowedPaths[i][0..userHomePath.len], userHomePath);
        @memcpy(allowedPaths[i][userHomePath.len .. userHomePath.len + pathRel.len], pathRel);
    }

    for (allowedPaths) |allowedPath| {

        // Buffer overflow protection
        if (pathString.len > std.fs.max_path_bytes) {
            Debug.log(.ERROR, "isFilePathAllowed: Provided path is too long (over std.fs.max_path_bytes).", .{});
            return false;
        }

        // Canonicalize the path string
        const realAllowedPath = std.fs.realpath(std.mem.sliceTo(&allowedPath, Character.NULL), &realPathBuffer) catch |err| {
            Debug.log(.ERROR, "isFilePathAllowed: Unable to resolve the real path of the allowed path. Error: {any}", .{err});
            return false;
        };

        if (std.mem.startsWith(u8, pathString, realAllowedPath)) return true;
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
    if (ext.len == 0) return false; // No extension cannot be an allowed one.

    for (allowedExtensionsArray) |allowedExt| {
        Debug.log(.DEBUG, "Comparing `{s}` and `{s}`", .{ ext, allowedExt });
        if (std.ascii.eqlIgnoreCase(ext, allowedExt)) return true;
    }

    return false;
}

/// Determines the ImageType enum based on the file path's extension.
/// This function performs a case-insensitive check for ".ISO" and ".IMG".
/// If the extension does not match either of those, it defaults to ImageType.Other.
fn getImageType(path: []const u8) ImageType {
    const ext = getExtensionFromPath(path);

    if (std.ascii.eqlIgnoreCase(ext, ".ISO")) return .ISO;
    if (std.ascii.eqlIgnoreCase(ext, ".IMG")) return .IMG;

    return .Other;
}

// --- Unit Tests ---

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
