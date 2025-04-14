const FilePicker = @import("FilePicker/Index.zig");
const USBDevicesList = @import("USBDevicesList/Index.zig");

const AppController = @import("../AppController.zig");

pub const Blueprint = union(enum) {
    FilePicker: *FilePicker.Component,
    USBDevicesList: *USBDevicesList.Component,

    pub fn setAppController(self: Blueprint, pAppController: *AppController) void {
        switch (self) {
            inline else => |s| s.appController = pAppController,
        }
    }

    pub fn getSelf(self: Blueprint) Blueprint {
        switch (self) {
            inline else => |s| return s,
        }
    }

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
