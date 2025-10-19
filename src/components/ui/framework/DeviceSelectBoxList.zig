const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElementCallbacks = UIFramework.UIElementCallbacks;
const PositionSpec = UIFramework.PositionSpec;
const SizeSpec = UIFramework.SizeSpec;
const UnitValue = UIFramework.UnitValue;

const DeviceSelectBox = @import("./DeviceSelectBox.zig");

const ArrayList = std.ArrayList;

const DeviceSelectBoxList = @This();

pub const ContextDestructor = *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void;

pub const Layout = struct {
    padding: f32 = 0,
    spacing: f32 = 0,
    row_height: f32 = 80,
};

pub const Config = struct {
    identifier: ?UIElementIdentifier = null,
    allocator: std.mem.Allocator,
    layout: Layout = .{},
    style: DeviceSelectBox.Style,
    callbacks: UIElementCallbacks = .{},
};

pub const EntryConfig = struct {
    deviceKind: DeviceSelectBox.DeviceKind,
    content: DeviceSelectBox.Content,
    callbacks: UIElementCallbacks = .{},
    selected: bool = false,
    enabled: bool = true,
    serviceId: ?usize = null,
    context: ?*anyopaque = null,
    context_dtor: ?ContextDestructor = null,
};

const Entry = struct {
    box: DeviceSelectBox,
    context: ?*anyopaque = null,
    context_dtor: ?ContextDestructor = null,
};

identifier: ?UIElementIdentifier = null,
allocator: std.mem.Allocator,
transform: Transform = .{},
layout: Layout,
style: DeviceSelectBox.Style,
entries: ArrayList(Entry),
active: bool = true,
layout_dirty: bool = true,
last_rect: rl.Rectangle = rectZero(),
callbacks: UIElementCallbacks = .{},

pub fn init(config: Config) DeviceSelectBoxList {
    return .{
        .identifier = config.identifier,
        .allocator = config.allocator,
        .transform = .{},
        .layout = config.layout,
        .style = config.style,
        .entries = ArrayList(Entry).empty,
        .callbacks = config.callbacks,
    };
}

pub fn start(self: *DeviceSelectBoxList) !void {
    self.transform.resolve();
    self.last_rect = self.transform.asRaylibRectangle();
    self.reflow();
}

pub fn update(self: *DeviceSelectBoxList) !void {
    if (!self.active) return;

    self.transform.resolve();
    const rect = self.transform.asRaylibRectangle();

    if (!rectEquals(rect, self.last_rect)) {
        self.last_rect = rect;
        self.layout_dirty = true;
    }

    if (self.layout_dirty) self.reflow();

    for (self.entries.items) |*entry| {
        try entry.box.update();
    }
}

pub fn draw(self: *DeviceSelectBoxList) !void {
    if (!self.active) return;

    for (self.entries.items) |*entry| {
        try entry.box.draw();
    }
}

pub fn onEvent(self: *DeviceSelectBoxList, event: UIEvent) void {
    switch (event) {
        .StateChanged => |e| {
            if (e.target) |target| {
                if (target != self.identifier) return;
                self.setActive(e.isActive);
            } else {
                self.setActive(e.isActive);
            }
        },
        else => {},
    }

    for (self.entries.items) |*entry| entry.box.onEvent(event);
    if (self.callbacks.onStateChange) |handler| handler.call(self.active);
}

pub fn setActive(self: *DeviceSelectBoxList, flag: bool) void {
    self.active = flag;
    for (self.entries.items) |*entry| entry.box.setActive(flag);
}

pub fn append(self: *DeviceSelectBoxList, entry_cfg: EntryConfig) !void {
    const new_box = DeviceSelectBox.init(.{
        .identifier = null,
        .deviceKind = entry_cfg.deviceKind,
        .content = entry_cfg.content,
        .style = self.style,
        .callbacks = entry_cfg.callbacks,
        .selected = entry_cfg.selected,
        .enabled = entry_cfg.enabled,
        .serviceId = entry_cfg.serviceId,
    });

    try self.entries.append(self.allocator, .{
        .box = new_box,
        .context = entry_cfg.context,
        .context_dtor = entry_cfg.context_dtor,
    });

    const idx = self.entries.items.len - 1;
    self.bindEntry(idx);
    try self.entries.items[idx].box.start();
    if (!self.active) self.entries.items[idx].box.setActive(false);
    self.layout_dirty = false;
}

pub fn clear(self: *DeviceSelectBoxList) void {
    while (self.entries.items.len > 0) {
        var entry = self.entries.pop();
        if (entry) |*en| {
            if (en.context_dtor) |dtor| if (en.context) |ctx| dtor(ctx, self.allocator);
            en.box.deinit();
        }
    }
    self.entries.clearRetainingCapacity();
    self.layout_dirty = true;
}

pub fn setSelected(self: *DeviceSelectBoxList, service_id: ?usize) void {
    for (self.entries.items) |*entry| {
        if (service_id) |id| {
            if (entry.box.serviceIdentifier()) |candidate| {
                entry.box.setSelected(candidate == id);
            } else entry.box.setSelected(false);
        } else {
            entry.box.setSelected(false);
        }
    }
}

pub fn deinit(self: *DeviceSelectBoxList) void {
    self.clear();
    self.entries.deinit(self.allocator);
}

fn reflow(self: *DeviceSelectBoxList) void {
    for (self.entries.items, 0..) |_, index| self.bindEntry(index);
    self.layout_dirty = false;
}

fn bindEntry(self: *DeviceSelectBoxList, index: usize) void {
    var entry = &self.entries.items[index];
    entry.box.transform.relativeTransform = &self.transform;

    const y_offset = self.layout.padding + @as(f32, @floatFromInt(index)) * (self.layout.row_height + self.layout.spacing);

    entry.box.transform.position = PositionSpec.mix(
        UnitValue.mix(0, self.layout.padding),
        UnitValue.mix(0, y_offset),
    );
    entry.box.transform.size = SizeSpec.mix(
        UnitValue.mix(1, -2 * self.layout.padding),
        UnitValue.pixels(self.layout.row_height),
    );
    entry.box.transform.resolve();
}

fn rectZero() rl.Rectangle {
    return rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
}

fn rectEquals(a: rl.Rectangle, b: rl.Rectangle) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}
