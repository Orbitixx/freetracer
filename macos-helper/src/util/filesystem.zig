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

const WRITE_BLOCK_SIZE = 1024 * 1_000;

pub fn writeISO(connection: XPCConnection, imageFile: std.fs.File, device: std.fs.File) !void {
    Debug.log(.INFO, "Begin writing prep...", .{});
    const writeBuffer = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(writeBuffer);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var previousProgress: u64 = 0;
    var currentProgress: u64 = 0;
    var xpcResponseTimer = try std.time.Timer.start();
    var overallTimer = try std.time.Timer.start();
    var bytesSinceUpdate: u64 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Writing ISO to device, please wait...", .{});

    while (currentByte < imageSize) {
        previousProgress = currentProgress;

        try imageFile.seekTo(currentByte);
        const bytesRead = try imageFile.read(writeBuffer);

        if (bytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached, final block: {d} at {d}!", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        // NOTE: Important to use the slice syntax here, otherwise if writing &writeBuffer
        // it only writes WRITE_BLOCK_SIZE blocks, meaning if the last block is smaller
        // then the data will likely be corrupted.
        try device.seekTo(currentByte);
        const bytesWritten = try device.write(writeBuffer[0..bytesRead]);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            Debug.log(.ERROR, "CRITICAL ERROR: failed to correctly write to device. Aborting...", .{});
            break;
        }

        const bytesWrittenU64 = @as(u64, @intCast(bytesWritten));
        currentByte += bytesWrittenU64;
        currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);
        bytesSinceUpdate += bytesWrittenU64;

        const elapsedNs = xpcResponseTimer.read();

        // Only send an XPC message if the progress moved at least 1%; throttle message send rate
        // TODO: Replace by XPC message barrier
        if (elapsedNs < 500_000 or currentProgress == previousProgress) {
            if (currentProgress != 100) continue;
        }

        const totalElapsedNs = overallTimer.read();
        const totalSeconds: f128 = if (totalElapsedNs == 0) 1.0e-9 else @as(f128, @floatFromInt(totalElapsedNs)) / 1_000_000_000.0;
        var avgRateFloat = @as(f128, @floatFromInt(currentByte)) / totalSeconds;
        if (!std.math.isFinite(avgRateFloat) or avgRateFloat <= 0) {
            avgRateFloat = 0;
        }

        const deltaTimeSeconds: f128 = if (elapsedNs == 0) 1.0e-9 else @as(f128, @floatFromInt(elapsedNs)) / 1_000_000_000.0;
        var instantRateFloat = @as(f128, @floatFromInt(bytesSinceUpdate)) / deltaTimeSeconds;
        if (!std.math.isFinite(instantRateFloat) or instantRateFloat <= 0) {
            instantRateFloat = 0;
        }

        const maxRate = @as(f128, @floatFromInt(std.math.maxInt(u64)));
        const averageByteWriteRate: u64 = if (avgRateFloat >= maxRate) std.math.maxInt(u64) else @intFromFloat(avgRateFloat);
        const instantaneousByteWriteRate: u64 = if (instantRateFloat >= maxRate) std.math.maxInt(u64) else @intFromFloat(instantRateFloat);

        const progressUpdate = XPCService.createResponse(.ISO_WRITE_PROGRESS);
        defer XPCService.releaseObject(progressUpdate);
        XPCService.createUInt64(progressUpdate, "write_progress", currentProgress);
        XPCService.createUInt64(progressUpdate, "write_rate", instantaneousByteWriteRate);
        XPCService.createUInt64(progressUpdate, "write_rate_avg", averageByteWriteRate);
        XPCService.createUInt64(progressUpdate, "write_bytes", currentByte);
        XPCService.createUInt64(progressUpdate, "write_total_size", imageSize);
        XPCService.connectionSendMessage(connection, progressUpdate);
        bytesSinceUpdate = 0;
        _ = xpcResponseTimer.lap();
    }

    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

pub fn verifyWrittenBytes(connection: XPCConnection, imageFile: std.fs.File, device: std.fs.File) !void {
    const imageByteBuffer = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(imageByteBuffer);
    const deviceByteBuffer = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(deviceByteBuffer);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var previousProgress: u64 = 0;
    var currentProgress: u64 = 0;
    var xpcResponseTimer = try std.time.Timer.start();

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Verifying ISO bytes written to device, please wait...", .{});

    while (currentByte < imageSize) {
        previousProgress = currentProgress;

        try imageFile.seekTo(currentByte);
        const imageBytesRead = try imageFile.read(imageByteBuffer);

        if (imageBytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached, final block: {d} at {d}!", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        try device.seekTo(currentByte);
        var deviceBytesReadTotal: usize = 0;
        while (deviceBytesReadTotal < imageBytesRead) {
            const remainingSlice = deviceByteBuffer[deviceBytesReadTotal..imageBytesRead];
            const deviceBytesRead = try device.read(remainingSlice);

            if (deviceBytesRead == 0) {
                Debug.log(
                    .ERROR,
                    "Device returned fewer bytes than expected during verification. Expected: {d}, received: {d}",
                    .{ imageBytesRead, deviceBytesReadTotal },
                );
                return error.MismatchingISOAndDeviceBytesDetected;
            }

            deviceBytesReadTotal += deviceBytesRead;
        }

        const imageSlice = imageByteBuffer[0..imageBytesRead];
        const deviceSlice = deviceByteBuffer[0..deviceBytesReadTotal];

        if (!std.mem.eql(u8, imageSlice, deviceSlice)) return error.MismatchingISOAndDeviceBytesDetected;

        currentByte += @as(u64, @intCast(imageBytesRead));
        currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);

        // Only send an XPC message if the progress moved at least 1%; throttle message send rate
        // TODO: Replace by XPC message barrier
        if (xpcResponseTimer.read() < 500_000 or currentProgress == previousProgress) {
            if (currentProgress != 100) continue;
        }

        // Debug.log(.INFO, "Verification progress: {d}", .{currentProgress});

        const progressUpdate = XPCService.createResponse(.WRITE_VERIFICATION_PROGRESS);
        defer XPCService.releaseObject(progressUpdate);
        XPCService.createUInt64(progressUpdate, "verification_progress", currentProgress);
        XPCService.connectionSendMessage(connection, progressUpdate);
        _ = xpcResponseTimer.lap();
    }

    Debug.log(.INFO, "Finished verifying ISO image written to device!", .{});
}
