const std = @import("std");
const env = @import("../env.zig");
const testing = std.testing;
const freetracer_lib = @import("freetracer-lib");

const ShutdownManager = @import("../managers/ShutdownManager.zig").ShutdownManagerSingleton;
const Debug = freetracer_lib.Debug;
const xpc = freetracer_lib.xpc;
const ISOParser = freetracer_lib.ISOParser;

const k = freetracer_lib.constants.k;
const c = freetracer_lib.c;
const String = freetracer_lib.String;
const Character = freetracer_lib.constants.Character;
const ImageType = freetracer_lib.types.ImageType;

const isFilePathAllowed = freetracer_lib.fs.isFilePathAllowed;

const XPCService = freetracer_lib.Mach.XPCService;
const XPCConnection = freetracer_lib.Mach.XPCConnection;
const XPCObject = freetracer_lib.Mach.XPCObject;

const WRITE_BLOCK_SIZE = 4096;

pub fn unwrapUserHomePath(buffer: *[std.fs.max_path_bytes]u8, restOfPath: []const u8) ![]u8 {
    const userDir = std.posix.getenv("HOME") orelse return error.HomeEnvironmentVariableIsNULL;

    @memcpy(buffer[0..userDir.len], userDir);
    @memcpy(buffer[userDir.len .. userDir.len + restOfPath.len], restOfPath);

    return buffer[0 .. userDir.len + restOfPath.len];
}

pub fn openFileValidated(unsanitizedIsoPath: []const u8, params: struct { userHomePath: []const u8, imageType: ImageType }) !std.fs.File {

    // Buffer overflow protection
    if (unsanitizedIsoPath.len > std.fs.max_path_bytes) {
        Debug.log(.ERROR, "Provided path is too long (over std.fs.max_path_bytes).", .{});
        return error.ISOFilePathTooLong;
    }

    if (params.userHomePath.len < 3) return error.UserHomePathTooShort;

    var realPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    var sanitizeStringBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    const imagePath = std.fs.realpath(unsanitizedIsoPath, &realPathBuffer) catch |err| {
        Debug.log(.ERROR, "Unable to resolve the real path of the povided path: {s}. Error: {any}", .{
            String.sanitizeString(&sanitizeStringBuffer, unsanitizedIsoPath),
            err,
        });
        return error.UnableToResolveRealISOPath;
    };

    const printableIsoPath = String.sanitizeString(&sanitizeStringBuffer, imagePath);

    if (imagePath.len < 8) {
        Debug.log(.ERROR, "Provided path is less than 8 characters long. Likely invalid, aborting for safety...", .{});
        return error.ISOFilePathTooShort;
    }

    const directory = std.fs.path.dirname(imagePath) orelse ".";
    const fileName = std.fs.path.basename(imagePath);

    if (!isFilePathAllowed(params.userHomePath, directory)) {
        Debug.log(.ERROR, "Provided path contains a disallowed part: {s}", .{printableIsoPath});
        return error.ISOFileContainsRestrictedPaths;
    }

    const dir = std.fs.openDirAbsolute(directory, .{ .no_follow = true }) catch |err| {
        Debug.log(.ERROR, "Unable to open the directory of specified ISO file. Aborting... Error: {any}", .{err});
        return error.UnableToOpenDirectoryOfSpecificedISOFile;
    };

    const imageFile = dir.openFile(fileName, .{ .mode = .read_only, .lock = .exclusive }) catch |err| {
        Debug.log(.ERROR, "Failed to open ISO file or obtain an exclusive lock. Error: {any}", .{err});
        return error.UnableToOpenISOFileOrObtainExclusiveLock;
    };

    const fileStat = imageFile.stat() catch |err| {
        Debug.log(.ERROR, "Failed to obtain ISO file stat. Error: {any}", .{err});
        return error.UnableToObtainISOFileStat;
    };

    if (fileStat.kind != std.fs.File.Kind.file) {
        Debug.log(
            .ERROR,
            "The provided ISO path is not a recognized file by file system. Symlinks and other kinds are not allowed. Kind used: {any}",
            .{fileStat.kind},
        );
        return error.InvalidISOFileKind;
    }

    // Minimum ISO system block: 16 sectors by 2048 bytes each + 1 sector for PVD contents.
    if (fileStat.size < 16 * 2048 + 1) return error.InvalidISOSystemStructure;

    if (params.imageType == .ISO) {
        const isoValidationResult = ISOParser.validateISOFileStructure(imageFile);

        // TODO: If ISO structure does not conform to ISO9660, prompt user to proceed or not.
        if (isoValidationResult != .ISO_VALID) {
            Debug.log(.ERROR, "Invalid ISO file structure detected. Aborting... Error code: {any}", .{isoValidationResult});
            return error.InvalidISOStructureDoesNotConformToISO9660;
        }
    }

    return imageFile;
}

pub fn writeISO(connection: XPCConnection, isoFile: std.fs.File, device: std.fs.File) !void {
    Debug.log(.DEBUG, "Begin writing prep...", .{});
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const fileStat = try isoFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var previousProgress: u64 = 0;
    var currentProgress: u64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Writing ISO to device, please wait...", .{});

    while (currentByte < imageSize) {
        previousProgress = currentProgress;

        try isoFile.seekTo(currentByte);
        const bytesRead = try isoFile.read(&writeBuffer);

        if (bytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached, final block: {d} at {d}!", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        // Important to use the slice syntax here, otherwise if writing &writeBuffer
        // it only writes WRITE_BLOCK_SIZE blocks, meaning if the last block is smaller
        // then the data will likely be corrupted.
        const bytesWritten = try device.write(writeBuffer[0..bytesRead]);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            Debug.log(.ERROR, "CRITICAL ERROR: failed to correctly write to device. Aborting...", .{});
            break;
        }

        currentByte += @as(u64, @intCast(bytesWritten));
        currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);

        // Only send an XPC message if the progress moved at least 1%
        if (currentProgress - previousProgress < 1) continue;

        const progressUpdate = XPCService.createResponse(.ISO_WRITE_PROGRESS);
        defer XPCService.releaseObject(progressUpdate);
        XPCService.createUInt64(progressUpdate, "write_progress", currentProgress);
        XPCService.connectionSendMessage(connection, progressUpdate);
    }

    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

pub fn verifyWrittenBytes(connection: XPCConnection, isoFile: std.fs.File, device: std.fs.File) !void {
    var isoByteBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;
    var deviceByteBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const fileStat = try isoFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var previousProgress: u64 = 0;
    var currentProgress: u64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Verifying ISO bytes written to device, please wait...", .{});

    while (currentByte < imageSize) {
        previousProgress = currentProgress;

        try isoFile.seekTo(currentByte);
        const imageBytesRead = try isoFile.read(&isoByteBuffer);

        if (imageBytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached, final block: {d} at {d}!", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        try device.seekTo(currentByte);
        const deviceBytesRead = try device.read(&deviceByteBuffer);

        if (deviceBytesRead == 0) break;

        if (deviceBytesRead != imageBytesRead) return error.MismatchingISOAndDeviceBytesDetected;

        const imageSlice = isoByteBuffer[0..imageBytesRead];
        const deviceSlice = deviceByteBuffer[0..deviceBytesRead];

        if (!std.mem.eql(u8, imageSlice, deviceSlice)) return error.MismatchingISOAndDeviceBytesDetected;

        currentByte += @as(u64, @intCast(imageBytesRead));
        currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);

        // Only send an XPC message if the progress moved at least 1%
        if (currentProgress - previousProgress < 1) continue;

        Debug.log(.INFO, "Verification progress: {d}", .{currentProgress});

        const progressUpdate = XPCService.createResponse(.WRITE_VERIFICATION_PROGRESS);
        defer XPCService.releaseObject(progressUpdate);
        XPCService.createUInt64(progressUpdate, "verification_progress", currentProgress);
        XPCService.connectionSendMessage(connection, progressUpdate);
    }

    Debug.log(.INFO, "Finished verifying ISO image written to device!", .{});
}

test "unwrapping user home path generates a correct path" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const expectedOutput = std.posix.getenv("HOME");
    try std.testing.expect(expectedOutput != null);

    const result: [:0]const u8 = @ptrCast(try unwrapUserHomePath(&buffer, ""));
    try std.testing.expect(std.mem.eql(u8, expectedOutput.?, result));
}

test "selecting an ISO in Documents folder is allowed" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
    const userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL;
    const path = try unwrapUserHomePath(&buffer, env.TEST_ISO_FILE_PATH);
    try std.testing.expect(isFilePathAllowed(userHomePath, path) == true);
}

test "selecting an file in other directories is disallowed" {
    var buffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

    const userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL;

    const path1: []const u8 = "/etc/sudoers";
    try std.testing.expect(isFilePathAllowed(userHomePath, path1) == false);

    const path2: []const u8 = "/dev/zero";
    try std.testing.expect(isFilePathAllowed(userHomePath, path2) == false);

    const path3: []const u8 = "/Library/LaunchDaemons/";
    try std.testing.expect(isFilePathAllowed(userHomePath, path3) == false);

    const path4: []const u8 = try unwrapUserHomePath(&buffer, "/Applications/");
    try std.testing.expect(isFilePathAllowed(userHomePath, path4) == false);

    const path5: []const u8 = try unwrapUserHomePath(&buffer, "/Notes/");
    try std.testing.expect(isFilePathAllowed(userHomePath, path5) == false);
}

test "calling openFileValidated returns a valid file handle" {
    const isoFile = try openFileValidated(
        // Simulated; during runtime, provided by the XPC client.
        env.USER_HOME_PATH ++ env.TEST_ISO_FILE_PATH,
        // Simulated; during runtime, provided securily by XPCService.getUserHomePath()
        .{ .userHomePath = std.posix.getenv("HOME") orelse return error.UserHomePathIsNULL },
    );

    defer isoFile.close();

    try std.testing.expect(@TypeOf(isoFile) == std.fs.File);
}
