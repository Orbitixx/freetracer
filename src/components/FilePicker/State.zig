const std = @import("std");

pub const FilePickerState = struct {
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    taskRunning: bool = false,
    taskDone: bool = false,
    taskError: ?anyerror = null,

    filePath: ?[:0]const u8 = null,

    pub fn deinit(self: FilePickerState) void {
        _ = self;
        // if (self.filePath) |path|
        //     self.allocator.free(path);
    }
};
