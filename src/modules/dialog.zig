const std = @import("std");
const Debug = @import("freetracer-lib").Debug;
const osdialog = @import("osdialog-zig").osdialog;

const ButtonsVariant = enum {
    OK,
    OK_CANCEL,
    YES_NO,
};

const DialogLevel = enum {
    ERROR,
    WARNING,
    INFO,
};

pub fn message(comptime fmt: [:0]const u8, args: anytype, buttons: ButtonsVariant, level: DialogLevel) bool {
    const argsCount = @typeInfo(@TypeOf(args)).@"struct".fields.len;

    var messageText = fmt;
    var messageBuff = std.mem.zeroes([512]u8);

    if (argsCount > 0) {
        messageText = std.fmt.bufPrintZ(messageBuff[0..], fmt, args) catch blk: {
            Debug.log(.ERROR, "Dialog failed to print message to buffer: {s}", .{fmt});
            break :blk fmt;
        };
    }

    const dialogButtons: osdialog.osdialog_message_buttons = switch (buttons) {
        .OK => osdialog.OSDIALOG_OK,
        .OK_CANCEL => osdialog.OSDIALOG_OK_CANCEL,
        .YES_NO => osdialog.OSDIALOG_YES_NO,
    };

    const dialogLevel: osdialog.osdialog_message_level = switch (level) {
        .INFO => osdialog.OSDIALOG_INFO,
        .WARNING => osdialog.OSDIALOG_WARNING,
        .ERROR => osdialog.OSDIALOG_ERROR,
    };

    return osdialog.osdialog_message(dialogLevel, dialogButtons, messageText.ptr) == @as(c_int, 1);
}

pub const PathAction = enum {
    OPEN_FILE,
    OPEN_DIR,
    SAVE_FILE,
};

pub const PathOptions = struct {
    dir: [:0]const u8 = "",
    filename: [:0]const u8 = "",
    filters: ?osdialog.struct_osdialog_filters = null,
};

pub fn path(allocator: std.mem.Allocator, action: PathAction, options: PathOptions) ?[:0]u8 {
    const fileAction: osdialog.osdialog_file_action = @intFromEnum(action);
    const cResult: [*c]u8 = osdialog.osdialog_file(fileAction, options.dir.ptr, options.filename.ptr, null);
    const cPath = catchNull(cResult) orelse return null;
    const zigPath: [:0]u8 = @ptrCast(std.mem.span(cPath));
    return allocator.dupeZ(u8, zigPath) catch return null;
}

fn catchNull(ptr: ?*anyopaque) ?[*c]u8 {
    const intermediate = ptr orelse return null;
    return @as([*c]u8, @ptrCast(intermediate));
}
