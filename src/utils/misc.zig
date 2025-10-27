const std = @import("std");
const osd = @import("osdialog");
const freetracer_lib = @import("freetracer-lib");
const c = freetracer_lib.c;

pub fn fromXPCThreadCallMainThreadDialog(callback: *const fn (?*anyopaque) callconv(.c) void) void {
    c.dispatch_async_f(c.dispatch_get_main_queue(), null, callback);
}
