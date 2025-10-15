const std = @import("std");
const UIFramework = @import("./import.zig");
const UIElement = UIFramework.UIElement;
const RelativeRef = UIFramework.RelativeRef;
const PositionSpec = UIFramework.PositionSpec;
const SizeSpec = UIFramework.SizeSpec;
const Transform = UIFramework.Transform;
const Rectangle = UIFramework.Rectangle;
const View = UIFramework.View;
const Text = UIFramework.Text;
const Textbox = UIFramework.Textbox;
const Texture = UIFramework.Texture;

const UIElementIdentifier = UIFramework.UIElementIdentifier;

pub const ElementChain = struct {
    allocator: std.mem.Allocator,
    el: UIElement, // value we’re building
    _id: ?[]const u8 = null, // optional string id for parent’s map
    _positionRef: ?RelativeRef = null,
    _sizeRef: ?RelativeRef = null,
    _relativeRef: ?*const Transform = null,
    relative: ?RelativeRef = null, // where to resolve against (Parent or NodeId)

    // ---- generic chainers (common Transform knobs) ----
    pub fn id(self: ElementChain, s: []const u8) ElementChain {
        var c = self;
        c._id = s;
        return c;
    }

    pub fn position(self: ElementChain, p: PositionSpec) ElementChain {
        var c = self;
        UIElement.transformPtr(&c.el).position = p;
        return c;
    }

    pub fn size(self: ElementChain, s: SizeSpec) ElementChain {
        var c = self;
        UIElement.transformPtr(&c.el).size = s;
        return c;
    }

    pub fn positionRef(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._positionRef = r;
        return c;
    }

    pub fn sizeRef(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._sizeRef = r;
        return c;
    }

    // pub fn relativeRef(self: ElementChain, t: ?*const Transform) ElementChain {
    //     var c = self;
    //     c._positionRef = r;
    //     return c;
    // }

    pub fn offset(self: ElementChain, dx: f32, dy: f32) ElementChain {
        var c = self;
        const tr = UIElement.transformPtr(&c.el);
        tr.offset_x += dx;
        tr.offset_y += dy;
        return c;
    }

    pub fn scale(self: ElementChain, v: f32) ElementChain {
        var c = self;
        UIElement.transformPtr(&c.el).scale = v;
        return c;
    }

    pub fn rotation(self: ElementChain, deg: f32) ElementChain {
        var c = self;
        UIElement.transformPtr(&c.el).rotation = deg;
        return c;
    }

    /// Place to the right edge of target id + gap px (top aligned).
    pub fn toRightOf(self: ElementChain, target_id: []const u8, gap_px: f32) ElementChain {
        return self.positionRef(.{ .NodeId = target_id }).position(.percent(1.0, 0.0)).offset(gap_px, 0);
    }
    /// Place below target id + gap px (left aligned).
    pub fn below(self: ElementChain, target_id: []const u8, gap_px: f32) ElementChain {
        return self.positionRef(.{ .NodeId = target_id }).position(.percent(0.0, 1.0)).offset(0, gap_px);
    }

    // ---- build protocol: add into a parent View ----
    pub fn buildInto(self: ElementChain, parent: *View) !void {
        // Apply the chosen stable ref to the element’s transform
        var me = self.el; // local copy
        const tr = UIElement.transformPtr(&me);
        tr.relativeRef = null; // prefer stable path

        if (self.relative) |r| tr.relative = r;
        if (self._positionRef) |r| tr.position_ref = r;
        if (self._sizeRef) |r| tr.size_ref = r;

        // Let parent own/resolve id mapping and resolver context
        if (self._id) |sid| {
            try parent.addChildNamed(sid, me, self.relative orelse .Parent);
        } else if (self.relative) |r| {
            try parent.addChildWithRelative(me, r);
        } else {
            try parent.addChild(me, null); // defaults to parent via legacy or resolver
        }
    }

    // ---- only valid if this ElementChain wraps a View ----
    pub fn children(self: ElementChain, kids: anytype) !View {
        // Extract the View value we’re wrapping (runtime-checked).
        var view_value: View = undefined;
        switch (self.el) {
            .View => |v| view_value = v, // copy the View out of the union
            else => return error.ChildrenOnNonView,
        }

        // Apply the intended relative (if any) to the View itself.
        if (self.relative) |r| {
            view_value.transform.relativeRef = null; // prefer stable path
            view_value.transform.relative = r;
        }

        if (self._positionRef) |r| view_value.transform.position_ref = r;
        if (self._sizeRef) |r| view_value.transform.size_ref = r;

        // Build children into this temporary View.
        inline for (kids) |kid| {
            try kid.buildInto(&view_value);
        }

        return view_value; // return the finished View by value
    }
};

// ------------------------------
// Minimal “factory” that returns ElementChain
// (Thin wrappers—no duplicate chainers.)
// ------------------------------
pub const UIChain = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UIChain {
        return .{ .allocator = allocator };
    }

    // Generic entry point if you want to wrap an already-built element yourself.
    pub fn element(self: UIChain, el: UIElement) ElementChain {
        return .{ .allocator = self.allocator, .el = el };
    }

    // Convenience makers — all return ElementChain
    pub const ViewConfig = struct {
        id: ?UIElementIdentifier = null,
        position: PositionSpec = .{},
        size: SizeSpec = .{},
        relativeRef: ?*const Transform = null,
        relative: ?RelativeRef = null,
        background: ?Rectangle = null,
    };

    pub fn view(self: UIChain, cfg: ViewConfig) ElementChain {
        var t: Transform = .{};
        t.position = cfg.position;
        t.size = cfg.size;
        t.relativeRef = cfg.relativeRef;
        t.relative = cfg.relative;
        return .{
            .allocator = self.allocator,
            .el = UIElement{ .View = View.init(
                self.allocator,
                cfg.id,
                t,
                cfg.background,
            ) },
        };
    }

    pub fn texture(self: UIChain, resource: anytype) ElementChain {
        const tex = Texture.init(null, resource, .{}, null);
        return .{ .allocator = self.allocator, .el = UIElement{ .Texture = tex } };
    }

    pub fn textbox(self: UIChain, value: [:0]const u8, style: anytype, options: anytype) ElementChain {
        const tb = Textbox.init(self.allocator, value, .{}, style, null, options);
        return .{ .allocator = self.allocator, .el = UIElement{ .Textbox = tb } };
    }
};
