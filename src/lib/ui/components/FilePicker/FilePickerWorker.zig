const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../../util/debug.zig");

const FilePickerState = @import("FilePickerTypes.zig").FilePickerState;

pub fn runFilePickerWorker(allocator: std.mem.Allocator, state: *FilePickerState) void {
    debug.print("Worker: Starting file picker...\n");

    // --- Perform the potentially blocking action ---
    // Let's assume osd.path allocates the returned path using the provided allocator
    // and returns null if the user cancels.
    var maybe_path: ?[]u8 = null;
    const maybe_error: ?anyerror = null;

    maybe_path = osd.path(allocator, .open, .{});
    if (maybe_path) |path| {
        debug.printf("\nFilePickerWorker: File picker returned path: {s}\n", .{path});
    } else if (maybe_error == null) {
        debug.print("\nFilePickerWorker: File picker cancelled or returned null.\n");
    }

    // --- Critical Section: Update Shared State ---
    state.mutex.lock();
    defer state.mutex.unlock();

    // Store results/errors
    state.filePath = maybe_path; // Transfer ownership of allocation to SharedState
    state.taskError = null;

    // Update flags
    state.taskDone = true;
    state.taskRunning = false;

    debug.print("\nFilePickerWorker: Updated shared state. Exiting.\n");
}
