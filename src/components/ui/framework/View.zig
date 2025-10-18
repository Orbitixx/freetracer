const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Debug = @import("freetracer-lib").Debug;

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const UIEvent = UIFramework.UIEvent;
const UIElementIdentifier = UIFramework.UIElementIdentifier;
const UIElement = UIFramework.UIElement;
const UIElementCallbacks = UIFramework.UIElementCallbacks;
const RelativeRef = UIFramework.RelativeRef;
const resolveRelative = UIFramework.resolveRelative;

const View = @This();

const ViewEventParams = struct {
    excludeSelf: bool = false,
};

identifier: ?UIElementIdentifier = null,
allocator: Allocator,
transform: Transform = .{},
background: ?Rectangle = null,
children: ArrayList(UIElement),
idMap: std.StringHashMap(usize),
callbacks: UIElementCallbacks = .{},

pub fn init(allocator: Allocator, identifier: ?UIElementIdentifier, transform: Transform, background: ?Rectangle) View {
    return .{
        .identifier = identifier,
        .allocator = allocator,
        .transform = transform,
        .background = background,
        .children = ArrayList(UIElement).empty,
        .idMap = std.StringHashMap(usize).init(allocator),
    };
}

pub fn start(self: *View) !void {
    Debug.log(.DEBUG, "View start() called.", .{});

    self.layoutSelf();

    for (self.children.items) |*child| {
        switch (child.*) {
            inline else => |*el| {
                el.transform._resolver_ctx = self;
                el.transform._resolver_fn = resolveRelative;
            },
        }
        try child.start();
    }
}

pub fn update(self: *View) !void {
    self.layoutSelf();
    for (self.children.items) |*child| {
        try child.update();
    }
}

pub fn draw(self: *View) !void {
    if (self.background) |*bg| try bg.draw();

    for (self.children.items) |*child| {
        try child.draw();
    }
}

pub fn deinit(self: *View) void {
    for (self.children.items) |*child| {
        child.deinit();
    }

    self.children.deinit(self.allocator);

    // Iterate over the StringHashMap and free owned string keys
    var iter = self.idMap.iterator();

    while (iter.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }

    self.idMap.deinit();
}

pub fn onEvent(self: *View, event: UIEvent) void {
    Debug.log(.DEBUG, "View recevied a UIEvent: {any}", .{event});

    switch (event) {
        .StateChanged => |e| {
            if (e.target) |target| if (target != self.identifier) return;
            if (self.callbacks.onStateChange) |onStateChange| onStateChange.function(self, e.isActive);
        },
        else => {},
    }
}

pub fn emitEvent(self: *View, event: UIEvent, params: ViewEventParams) void {
    if (!params.excludeSelf) self.onEvent(event);

    for (self.children.items) |*child| {
        child.onEvent(event);
    }
}

fn layoutSelf(self: *View) void {
    self.transform.resolve();

    if (self.background) |*bg| {
        bg.transform = self.transform;
    }
}

pub fn addChild(self: *View, child: UIElement, relativeTransform: ?*Transform) !void {
    var mutableChild = child;

    switch (mutableChild) {
        inline else => |*el| {
            if (relativeTransform) |rt| el.transform.relativeTransform = rt else el.transform.relativeTransform = &self.transform;
            el.transform._resolver_ctx = self;
            el.transform._resolver_fn = resolveRelative;
        },
    }

    try self.children.append(self.allocator, mutableChild);
}

/// Adds a child with a stable string ID and an ID-based relative reference.
/// Example:
///   try view.addChildNamed("step_icon", .{ .Texture = ... }, .Parent);
///   try view.addChildNamed("header", .{ .Textbox = ... }, .{ .NodeId = "step_icon" });
pub fn addChildNamed(self: *View, id: []const u8, child: UIElement, relative: RelativeRef) !void {
    var mutableChild = child;

    // Set resolver context and relative ref
    switch (mutableChild) {
        inline else => |*el| {
            el.transform.relativeTransform = null; // ignore legacy path for this child
            el.transform.relative = relative;
            el.transform._resolver_ctx = self;
            el.transform._resolver_fn = resolveRelative;
        },
    }

    // Append, then map the ID -> index (dup the string to own it)
    try self.children.append(self.allocator, mutableChild);
    const idx = self.children.items.len - 1;
    const owned = try self.allocator.dupe(u8, id);

    try self.idMap.put(owned, idx);
}

pub fn addChildWithRelative(self: *View, child: UIElement, relative: RelativeRef) !void {
    var mutableChild = child;

    switch (mutableChild) {
        inline else => |*el| {
            el.transform.relativeTransform = null; // ignore legacy pointer
            el.transform.relative = relative;
            // Resolver context will be rebound in start(); set a provisional one now:
            el.transform._resolver_ctx = self;
            el.transform._resolver_fn = resolveRelative;
        },
    }

    try self.children.append(self.allocator, mutableChild);
}
