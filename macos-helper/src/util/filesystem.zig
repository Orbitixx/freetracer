//! Privileged Helper Filesystem Utilities
//!
//! Provides low-level disk I/O operations for the privileged helper process.
//! Handles the critical operations of writing images to devices and
//! verifying the written data for data integrity.
//!
//! Key Operations:
//! - Image writing with optimized block-aligned buffering
//! - Device capacity probing for safe write chunk sizes
//! - Real-time progress reporting via XPC to GUI
//! - Byte-by-byte verification of written data
//! - Aggressive caching optimization (fcntl flags)
//!
//! Performance Characteristics:
//! - Uses direct write to device (no extra buffering layers)
//! - Probes device capabilities (block size, max write blocks)
//! - Adaptive chunk sizing (4-16 MB, aligned to device blocks)
//! - Batched progress updates to reduce XPC overhead
//! - Prefetching enabled on source image
//!
//! Reliability:
//! - Single fsync() at end of write operation (via Zig's sync() abstraction)
//! - Byte-by-byte verification with mismatch detection
//! - Comprehensive error logging

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

const MIN_WRITE_SIZE = 4 * 1_024 * 1_024; // 4 MB minimum - safety threshold
const MAX_WRITE_SIZE = 16 * 1_024 * 1_024; // 16 MB maximum - prevent excessive memory use

/// Probes device capabilities and returns optimal write chunk size.
/// Queries the device for physical block size and maximum write blocks,
/// then calculates an optimal chunk size aligned to device boundaries.
/// This optimization ensures efficient I/O without overwhelming the device.
///
/// `Arguments`:
///   device: Open device file handle
///
/// `Returns`:
///   Optimal write chunk size in bytes (4-16 MB, block-aligned)
///   Falls back to 4 MB on any error or suspicious device response
///
/// `Optimization Strategy`:
///   1. Query DKIOCGETBLOCKSIZE (device physical block size, default 4KB)
///   2. Query DKIOCGETMAXBLOCKCOUNTWRITE (max blocks per write, default 1024)
///   3. Calculate: blockSize * maxBlockCount
///   4. Clamp to [4MB, 16MB] range for safety
///   5. Align down to nearest block size multiple for device alignment
///   6. Fall back to 4MB if result is 0
///
/// `Performance Impact`:
///   - Larger chunks = fewer I/O syscalls, better throughput
///   - Device-aligned chunks = optimal filesystem performance
///   - 4-16MB range balances memory use vs I/O efficiency
///
/// `Safety`:
///   - Returns 4MB on any ioctl failure (conservative default)
///   - Clamps to prevent excessive memory allocation
///   - Validates non-zero values before use
fn probeDeviceWriteSize(device: std.fs.File) u64 {
    const fd: c_int = @intCast(device.handle);
    var blockSize: u32 = 4096; // Default: 4KB sectors
    var maxBlockCount: u32 = 0;

    // Query physical block size
    if (c.ioctl(fd, c.DKIOCGETBLOCKSIZE, @as(?*c_uint, @ptrCast(&blockSize))) != 0 or blockSize == 0) {
        Debug.log(.WARNING, "DKIOCGETBLOCKSIZE failed, using default 4KB block size", .{});
        blockSize = 4096;
    } else {
        Debug.log(.INFO, "Device block size: {d} bytes", .{blockSize});
    }

    // Query max write blocks
    if (c.ioctl(fd, c.DKIOCGETMAXBLOCKCOUNTWRITE, @as(?*c_uint, @ptrCast(&maxBlockCount))) != 0 or maxBlockCount == 0) {
        Debug.log(.WARNING, "DKIOCGETMAXBLOCKCOUNTWRITE failed, using default 1024 blocks", .{});
        maxBlockCount = 1024;
    } else {
        Debug.log(.INFO, "Device max block count: {d}", .{maxBlockCount});
    }

    // Calculate: (blockSize * maxBlockCount), then clamp to [4MiB, 16MiB]
    const calculated = @as(u64, @intCast(blockSize)) * @as(u64, @intCast(maxBlockCount));
    const clamped = std.math.clamp(calculated, MIN_WRITE_SIZE, MAX_WRITE_SIZE);

    // Round down to nearest multiple of blockSize for alignment
    const aligned = (clamped / blockSize) * blockSize;
    const finalSize = if (aligned > 0) aligned else MIN_WRITE_SIZE;

    Debug.log(.INFO, "Probed write chunk size: {d} bytes ({d} MB, aligned to {d}-byte blocks)", .{
        finalSize,
        finalSize / (1024 * 1024),
        blockSize,
    });

    return finalSize;
}

/// Writes an image to target device with aggressive performance optimization.
/// Core operation: read from image file, write directly to device.
/// Real-time progress is sent to GUI via XPC with instantaneous and average rates.
///
/// `Arguments`:
///   connection: XPC connection to GUI for progress updates
///   imageFile: Open ISO image file (read position at start)
///   deviceHandle: Target device to write to
///
/// `Errors`:
///   Propagates file I/O errors from read/write operations
///
/// `Performance Optimizations`:
///   1. fcntl(F_NOCACHE): Disable filesystem caching on both files
///      - Avoids memory bloat from buffering large writes
///      - Forces direct I/O to device
///   2. fcntl(F_RDAHEAD): Enable read-ahead on image
///      - Kernel pre-fetches next blocks while current write is in progress
///      - Reduces read latency on sequential scans
///   3. Device-optimal chunk size (4-16 MB block-aligned)
///      - Minimizes syscall overhead
///      - Aligns with device's native I/O capabilities
///   4. Single fsync() at end via Zig's sync()
///      - Ensures all data reaches device
///      - Amortized cost compared to sync after each chunk
///
/// `Progress Reporting`:
///   Sends updates on dual triggers to prevent both flooding XPC and stale UI:
///   - Byte-based: Every 8 MB written (avoids excessive overhead)
///   - Time-based: Every 100 ms (ensures responsive UI even on slow devices)
///   - Completion: Final update when write finishes
///
/// `Reported Metrics`:
///   - write_progress: Percentage complete (0-100)
///   - write_rate: Current instantaneous write rate (bytes/sec)
///   - write_rate_avg: Average rate since start (bytes/sec)
///   - write_bytes: Total bytes written so far
///   - write_total_size: Total image size
pub fn writeImage(connection: XPCConnection, imageFile: std.fs.File, deviceHandle: DeviceHandle) !void {
    Debug.log(.INFO, "Begin writing prep...", .{});

    const device = deviceHandle.raw;

    const noCacheDevice = c.fcntl(device.handle, c.F_NOCACHE, @as(c_int, 1));
    const noCacheImage = c.fcntl(imageFile.handle, c.F_NOCACHE, @as(c_int, 1));
    const imagePrefetcher = c.fcntl(imageFile.handle, c.F_RDAHEAD, @as(c_int, 1));

    Debug.log(.INFO, "fcntl results are: device = {d}, image = {d}, prefetch = {d}", .{ noCacheDevice, noCacheImage, imagePrefetcher });

    // Probe device for optimal write chunk size
    const CHUNK_SIZE = probeDeviceWriteSize(device);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    // Allocate single read buffer (no extra buffering layer)
    const readBuffer = try std.heap.page_allocator.alloc(u8, CHUNK_SIZE);
    defer std.heap.page_allocator.free(readBuffer);

    var xpcResponseTimer = try std.time.Timer.start();
    var overallTimer = try std.time.Timer.start();

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Writing image to device with {d}MB chunks, please wait...", .{CHUNK_SIZE / (1024 * 1024)});

    // Seek both files to start
    try imageFile.seekTo(0);
    try device.seekTo(0);

    // Progress tracking variables
    var currentByte: u64 = 0;
    var lastProgressUpdateByte: u64 = 0;
    var bytesSinceUpdate: u64 = 0;
    var timerCheckCounter: u32 = 0;

    const PROGRESS_UPDATE_INTERVAL_BYTES = 8 * 1_024 * 1_024; // Update UI every 8MB
    const PROGRESS_UPDATE_INTERVAL_NS = 100_000_000; // Also update every 100ms
    const TIMER_CHECK_INTERVAL = 100; // Check elapsed time every N iterations

    while (currentByte < imageSize) {
        const bytesRead = try imageFile.read(readBuffer);

        if (bytesRead == 0) {
            Debug.log(.INFO, "End of image file reached at byte: {d}", .{currentByte});
            break;
        }

        // Direct write to device (no extra buffering)
        try device.writeAll(readBuffer[0..bytesRead]);

        currentByte += @as(u64, @intCast(bytesRead));
        bytesSinceUpdate += @as(u64, @intCast(bytesRead));

        // Check if we should send progress update
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
            const currentProgress = try std.math.divFloor(u64, currentByte * 100, imageSize);

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

    // Single sync at the end to ensure all data is written to disk
    try device.sync();

    Debug.log(.INFO, "Finished writing image to device!", .{});
}

// ============================================================================
// VERIFICATION OPERATION - Byte-by-byte integrity check
// ============================================================================

/// Verifies that data written to device matches source ISO image exactly.
/// Critical final step: ensures write completed successfully and uncorrupted.
/// Reads chunks from both image and device, comparing sequentially.
///
/// `Arguments`:
///   connection: XPC connection to GUI for progress updates
///   imageFile: Source ISO image file
///   deviceHandle: Target device to verify
///
/// `Errors`:
///   error.MismatchingISOAndDeviceBytesDetected: Byte mismatch found
///   File I/O errors from read operations
///
/// `Verification Strategy`:
///   1. Use same probed chunk size as writeISO (consistency)
///   2. Read chunk from image, read same amount from device
///   3. Compare byte-by-byte (std.mem.eql)
///   4. Return error immediately on first mismatch (fail-fast)
///   5. Send progress updates with same batching as write
///
/// `Performance Considerations`:
///   - Allocates two buffers (device may cache differently than image)
///   - Sequential reads are fast (kernel-optimized)
///   - Verification is slower than write but essential
///   - Batched progress updates prevent XPC saturation
///   - Same 8MB/100ms update intervals as write
///
/// `Data Integrity`:
///   - Detects bit flips, write failures, or device issues
///   - Catches silent data corruption that write() doesn't detect
///   - Essential for bootable media (bad sectors corrupt boot)
///
/// `Error Handling`:
///   - Detects device returning fewer bytes than expected (I/O error)
///   - Fails fast on first mismatch (no partial passes)
///   - Logs mismatch details for debugging
///
/// `Note`:
///   This is deliberately slow and thorough - we verify the entire image
///   to ensure correctness, not speed. A failed verify is better than
///   a silent corruption that prevents boot.
pub fn verifyWrittenBytes(connection: XPCConnection, imageFile: std.fs.File, deviceHandle: DeviceHandle) !void {
    const device = deviceHandle.raw;

    // Use the same probed chunk size for consistency
    const CHUNK_SIZE = probeDeviceWriteSize(device);

    // Batch progress updates to reduce XPC message overhead
    const PROGRESS_UPDATE_INTERVAL_BYTES = 8 * 1_024 * 1_024; // Update UI every 8MB
    const PROGRESS_UPDATE_INTERVAL_NS = 100_000_000; // Also update every 100ms to prevent XPC saturation
    const TIMER_CHECK_INTERVAL = 100; // Check elapsed time every N iterations

    const imageByteBuffer = try std.heap.page_allocator.alloc(u8, CHUNK_SIZE);
    defer std.heap.page_allocator.free(imageByteBuffer);
    const deviceByteBuffer = try std.heap.page_allocator.alloc(u8, CHUNK_SIZE);
    defer std.heap.page_allocator.free(deviceByteBuffer);

    const fileStat = try imageFile.stat();
    const imageSize = fileStat.size;

    var currentByte: u64 = 0;
    var lastProgressUpdateByte: u64 = 0;
    var currentProgress: u64 = 0;
    var xpcResponseTimer = try std.time.Timer.start();
    var timerCheckCounter: u32 = 0;

    Debug.log(.INFO, "File and device are opened successfully! File size: {d}", .{imageSize});
    Debug.log(.INFO, "Verifying image bytes written to device with {d}MB chunks, please wait...", .{CHUNK_SIZE / (1024 * 1024)});

    // Seek both files to start
    try imageFile.seekTo(0);
    try device.seekTo(0);

    while (currentByte < imageSize) {
        // Read sequentially from both files (files maintain position)
        const imageBytesRead = try imageFile.read(imageByteBuffer);

        if (imageBytesRead == 0) {
            Debug.log(.INFO, "End of image file reached at byte: {d}", .{currentByte});
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

    Debug.log(.INFO, "Finished verifying image written to device!", .{});
}
