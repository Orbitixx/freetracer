const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../lib/util/debug.zig");

const ComponentState = @import("State.zig").FilePickerState;

pub fn runFilePickerWorker(allocator: std.mem.Allocator, state: *ComponentState) void {
    debug.print("\nWorker: Starting file picker...");

    // --- Perform the potentially blocking action ---
    // Let's assume osd.path allocates the returned path using the provided allocator
    // and returns null if the user cancels.
    var maybe_path: ?[]const u8 = null;
    _ = allocator;

    // const maybe_error: ?anyerror = null;

    // maybe_path = osd.path(allocator, .open, .{});
    // if (maybe_path) |path| {
    //     debug.printf("\nFilePickerWorker: File picker returned path: {s}\n", .{path});
    // } else if (maybe_error == null) {
    //     debug.print("\nFilePickerWorker: File picker cancelled or returned null.\n");
    // }
    //

    std.Thread.sleep(2 * std.time.ns_per_s);
    maybe_path = "/some/test/path/";

    // --- Critical Section: Update Shared State ---
    state.mutex.lock();
    defer state.mutex.unlock();

    // Store results/errors
    state.filePath = maybe_path; // Transfer ownership of allocation to SharedState
    state.taskError = null;

    // Update flags
    state.taskDone = true;
    state.taskRunning = false;

    debug.print("\nFilePickerWorker: Updated shared state. Exiting...");
}
