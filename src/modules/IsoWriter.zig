const std = @import("std");
const debug = @import("../lib/util/debug.zig");

const USBStorageDevice = @import("../modules/macos/MacOSTypes.zig").USBStorageDevice;

pub const WRITE_BLOCK_SIZE = 4096;

pub fn write(isoPath: []const u8, devicePath: []const u8) !void {
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const isoFile: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer isoFile.close();

    const device = try std.fs.openFileAbsolute(devicePath, .{ .mode = .read_write, .lock = .exclusive });
    defer device.close();

    const fileStat = try isoFile.stat();
    const ISO_SIZE = fileStat.size;

    var currentByte: u64 = 0;

    debug.print("[*] Writing ISO to device, please wait...\n");

    while (currentByte < ISO_SIZE) {
        try isoFile.seekTo(currentByte);
        const bytesRead = try isoFile.read(&writeBuffer);

        if (bytesRead == 0) {
            debug.printf("[v] End of ISO File reached, final block: {d} at {d}!\n", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        // Important to use the slice syntax here, otherwise if writing &writeBuffer
        // it only writes WRITE_BLOCK_SIZE blocks, meaning if the last block is smaller
        // then the data will likely be corrupted.
        const bytesWritten = try device.write(writeBuffer[0..bytesRead]);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            debug.print("CRITICAL ERROR: failed to correctly write to device. Aborting...");
            break;
        }

        currentByte += WRITE_BLOCK_SIZE;
    }

    try device.sync();

    debug.print("[v] Finished writing ISO image to device!");
}

pub const IOKitWriteError = error{
    MismatchingBytesWrittenAndBytesRead,
};

pub fn writeIOKit(device: *const USBStorageDevice, isoPath: []const u8) !void {
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const isoFile: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer isoFile.close();

    const fileStat = try isoFile.stat();
    const ISO_SIZE = fileStat.size;

    try @constCast(device).open();

    var currentByte: u64 = 0;

    debug.print("[*] Writing ISO to device, please wait...\n");

    while (currentByte < ISO_SIZE) {
        try isoFile.seekTo(currentByte);

        const bytesRead = try isoFile.read(&writeBuffer);

        if (bytesRead == 0) {
            debug.printf("[v] End of ISO File reached, final block: {d} at {d}!\n", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        const bytesWritten = try device.writeBlocks(&writeBuffer, @as(u64, @intCast(currentByte / WRITE_BLOCK_SIZE)), 1);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            debug.print("CRITICAL ERROR: failed to correctly write to device. Aborting...");
            return IOKitWriteError.MismatchingBytesWrittenAndBytesRead;
        }

        currentByte += WRITE_BLOCK_SIZE;
    }

    debug.print("[v] Finished writing ISO image to device!");
}
