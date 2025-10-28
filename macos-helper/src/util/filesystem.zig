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
const DeviceHandle = freetracer_lib.device.DeviceHandle;

const isFilePathAllowed = freetracer_lib.fs.isFilePathAllowed;

const XPCService = freetracer_lib.Mach.XPCService;
const XPCConnection = freetracer_lib.Mach.XPCConnection;
const XPCObject = freetracer_lib.Mach.XPCObject;

pub fn writeISO(connection: XPCConnection, imageFile: std.fs.File, deviceHandle: DeviceHandle) !void {
    Debug.log(.INFO, "Begin writing prep...", .{});

    const device = deviceHandle.raw;
    // const deviceStat = try device.stat();

    const noCacheDevice = c.fcntl(device.handle, c.F_NOCACHE, @as(c_int, 1));
    const noCacheImage = c.fcntl(imageFile.handle, c.F_NOCACHE, @as(c_int, 1));
    const imagePrefetcher = c.fcntl(imageFile.handle, c.F_RDAHEAD, @as(c_int, 1));

    Debug.log(.INFO, "fcntl results are: device = {d}, image = {d}, prefetch = {d}", .{ noCacheDevice, noCacheImage, imagePrefetcher });

    // c.posix_fallocate(device.handle, 0, bytes)

    // Use optimized block size for USB/SD devices
    const WRITE_BLOCK_SIZE = 4 * 1_024 * 1_024; // 4 MB block size

    // Batch progress updates to reduce XPC message overhead
    const PROGRESS_UPDATE_INTERVAL_BYTES = 8 * 1_024 * 1_024; // Update UI every 8MB
    const PROGRESS_UPDATE_INTERVAL_NS = 100_000_000; // Also update every 100ms to prevent XPC saturation
    const TIMER_CHECK_INTERVAL = 100; // Check elapsed time every N iterations

    // Double-buffering: allocate two buffers to enable prefetch while writing
    const buffer1 = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(buffer1);
    const buffer2 = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(buffer2);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var lastProgressUpdateByte: u64 = 0;
    var currentProgress: u64 = 0;
    var xpcResponseTimer = try std.time.Timer.start();
    var overallTimer = try std.time.Timer.start();
    var bytesSinceUpdate: u64 = 0;
    var iterationCount: u32 = 0;
    var timerCheckCounter: u32 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Writing ISO to device with {d}MB blocks (optimized for large files), please wait...", .{WRITE_BLOCK_SIZE / (1024 * 1024)});

    // Seek both files to start
    try imageFile.seekTo(0);
    try device.seekTo(0);

    while (currentByte < imageSize) {
        // Use double-buffering: alternate between two buffers
        // This allows OS to prefetch into one buffer while we write from the other
        const readBuffer = if (iterationCount % 2 == 0) buffer1 else buffer2;
        const bytesRead = try imageFile.read(readBuffer);

        if (bytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached at byte: {d}", .{currentByte});
            break;
        }

        // NOTE: Important to use the slice syntax here, otherwise if writing &readBuffer
        // it only writes WRITE_BLOCK_SIZE bytes, meaning if the last block is smaller
        // then the data will likely be corrupted.
        const bytesWritten = try device.write(readBuffer[0..bytesRead]);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            Debug.log(.ERROR, "CRITICAL ERROR: failed to correctly write to device. Aborting...", .{});
            break;
        }

        const bytesWrittenU64 = @as(u64, @intCast(bytesWritten));
        currentByte += bytesWrittenU64;
        bytesSinceUpdate += bytesWrittenU64;
        iterationCount += 1;

        // Batch progress updates to reduce XPC overhead
        // Check byte-based updates always, but only check time-based updates periodically
        const bytesSincLastUpdate = currentByte - lastProgressUpdateByte;
        const shouldUpdateByBytes = bytesSincLastUpdate >= PROGRESS_UPDATE_INTERVAL_BYTES;
        const isComplete = currentByte >= imageSize;

        var shouldUpdateByTime = false;
        timerCheckCounter += 1;
        if (timerCheckCounter >= TIMER_CHECK_INTERVAL) {
            const elapsedNsSinceLastUpdate = xpcResponseTimer.read();
            shouldUpdateByTime = elapsedNsSinceLastUpdate >= PROGRESS_UPDATE_INTERVAL_NS;
            timerCheckCounter = 0;
        }

        if (shouldUpdateByBytes or shouldUpdateByTime or isComplete) {
            currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);

            const totalElapsedNs = overallTimer.read();
            const totalSeconds: f128 = if (totalElapsedNs == 0) 1.0e-9 else @as(f128, @floatFromInt(totalElapsedNs)) / 1_000_000_000.0;
            var avgRateFloat = @as(f128, @floatFromInt(currentByte)) / totalSeconds;
            if (!std.math.isFinite(avgRateFloat) or avgRateFloat <= 0) {
                avgRateFloat = 0;
            }

            const elapsedNsSinceLastUpdate = xpcResponseTimer.read();
            const deltaTimeSeconds: f128 = if (elapsedNsSinceLastUpdate == 0) 1.0e-9 else @as(f128, @floatFromInt(elapsedNsSinceLastUpdate)) / 1_000_000_000.0;
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

            lastProgressUpdateByte = currentByte;
            bytesSinceUpdate = 0;
            _ = xpcResponseTimer.lap();
        }
    }

    // Final sync to ensure all data is written
    try device.sync();

    Debug.log(.INFO, "Finished writing ISO image to device!", .{});
}

pub fn verifyWrittenBytes(connection: XPCConnection, imageFile: std.fs.File, deviceHandle: DeviceHandle) !void {
    const device = deviceHandle.raw;

    // Use optimized block size for USB/SD devices
    const WRITE_BLOCK_SIZE = 4 * 1_024 * 1_024; // 4 MB block size

    // Batch progress updates to reduce XPC message overhead
    const PROGRESS_UPDATE_INTERVAL_BYTES = 8 * 1_024 * 1_024; // Update UI every 8MB
    const PROGRESS_UPDATE_INTERVAL_NS = 100_000_000; // Also update every 100ms to prevent XPC saturation
    const TIMER_CHECK_INTERVAL = 100; // Check elapsed time every N iterations

    const imageByteBuffer = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(imageByteBuffer);
    const deviceByteBuffer = try std.heap.page_allocator.alloc(u8, WRITE_BLOCK_SIZE);
    defer std.heap.page_allocator.free(deviceByteBuffer);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var lastProgressUpdateByte: u64 = 0;
    var currentProgress: u64 = 0;
    var xpcResponseTimer = try std.time.Timer.start();
    var iterationCount: u32 = 0;
    var timerCheckCounter: u32 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Verifying ISO bytes written to device with {d}MB blocks (optimized), please wait...", .{WRITE_BLOCK_SIZE / (1024 * 1024)});

    // Seek both files to start
    try imageFile.seekTo(0);
    try device.seekTo(0);

    while (currentByte < imageSize) {
        // Read sequentially from both files (files maintain position)
        const imageBytesRead = try imageFile.read(imageByteBuffer);

        if (imageBytesRead == 0) {
            Debug.log(.INFO, "End of ISO File reached at byte: {d}", .{currentByte});
            break;
        }

        // Read from device sequentially (matching position in image file)
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
        iterationCount += 1;

        // Batch progress updates to reduce XPC overhead
        // Check byte-based updates always, but only check time-based updates periodically
        const bytesSincLastUpdate = currentByte - lastProgressUpdateByte;
        const shouldUpdateByBytes = bytesSincLastUpdate >= PROGRESS_UPDATE_INTERVAL_BYTES;
        const isComplete = currentByte >= imageSize;

        var shouldUpdateByTime = false;
        timerCheckCounter += 1;
        if (timerCheckCounter >= TIMER_CHECK_INTERVAL) {
            const elapsedNsSinceLastUpdate = xpcResponseTimer.read();
            shouldUpdateByTime = elapsedNsSinceLastUpdate >= PROGRESS_UPDATE_INTERVAL_NS;
            timerCheckCounter = 0;
        }

        if (shouldUpdateByBytes or shouldUpdateByTime or isComplete) {
            currentProgress = try std.math.divFloor(u64, currentByte * @as(u64, 100), imageSize);

            const progressUpdate = XPCService.createResponse(.WRITE_VERIFICATION_PROGRESS);
            defer XPCService.releaseObject(progressUpdate);
            XPCService.createUInt64(progressUpdate, "verification_progress", currentProgress);
            XPCService.connectionSendMessage(connection, progressUpdate);

            lastProgressUpdateByte = currentByte;
            _ = xpcResponseTimer.lap();
        }
    }

    Debug.log(.INFO, "Finished verifying ISO image written to device!", .{});
}
