const std = @import("std");
const debug = @import("../lib/util/debug.zig");

pub const WRITE_BLOCK_SIZE = 4096;

pub fn write(isoPath: []const u8, devicePath: []const u8) !void {
    var writeBuffer: [WRITE_BLOCK_SIZE]u8 = undefined;

    const isoFile: std.fs.File = try std.fs.cwd().openFile(isoPath, .{ .mode = .read_only });
    defer isoFile.close();

    const device = try std.fs.openFileAbsolute(devicePath, .{ .mode = .read_write });
    defer device.close();

    const ISO_SIZE = try isoFile.stat().size;

    var currentByte = 0;

    debug.print("\n[*] Writing ISO to device, please wait...\n");

    while (currentByte < ISO_SIZE) {
        try isoFile.seekTo(currentByte * WRITE_BLOCK_SIZE);
        const bytesRead = try isoFile.read(&writeBuffer);

        if (bytesRead == 0) {
            debug.printf("\n[v] End of ISO File reached, final block: {d} at {d}!\n", .{ currentByte / WRITE_BLOCK_SIZE, currentByte });
            break;
        }

        const bytesWritten = try device.write(&writeBuffer);

        if (bytesWritten != bytesRead or bytesWritten == 0) {
            debug.print("\nCRITICAL ERROR: failed to correctly write to device. Aborting...");
            break;
        }

        currentByte += WRITE_BLOCK_SIZE;
    }

    try device.sync();

    debug.print("\n[v] Finished writing ISO image to device!");
}
