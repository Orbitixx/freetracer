const FilePicker = @import("FilePicker/Index.zig");

pub const Blueprint = union(enum) {
    FilePicker: *FilePicker.Component,

    pub fn draw(self: Blueprint) void {
        switch (self) {
            inline else => |s| s.draw(),
        }
    }

    pub fn update(self: Blueprint) void {
        switch (self) {
            inline else => |s| s.update(),
        }
    }

    pub fn deinit(self: Blueprint) void {
        switch (self) {
            inline else => |s| s.deinit(),
        }
    }
};
