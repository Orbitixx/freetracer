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
const FileDropzone = UIFramework.FileDropzone;
const SpriteButton = UIFramework.SpriteButton;
const DeviceSelectBox = UIFramework.DeviceSelectBox;
const DeviceSelectBoxList = UIFramework.DeviceSelectBoxList;
const ProgressBox = UIFramework.ProgressBox;

const UIElementIdentifier = UIFramework.UIElementIdentifier;

pub const ElementChain = struct {
    allocator: std.mem.Allocator,
    el: UIElement, // UIElement being built by the chain
    identifier: ?UIElementIdentifier = null,
    _active: bool = true,
    _id: ?[]const u8 = null,
    _positionRef: ?RelativeRef = null,
    _sizeRef: ?RelativeRef = null,
    _positionRefX: ?RelativeRef = null,
    _positionRefY: ?RelativeRef = null,
    _sizeRefWidth: ?RelativeRef = null,
    _sizeRefHeight: ?RelativeRef = null,
    _relativeTransform: ?*const Transform = null,
    _positionTransformX: ?*const Transform = null,
    _positionTransformY: ?*const Transform = null,
    _sizeTransformWidth: ?*const Transform = null,
    _sizeTransformHeight: ?*const Transform = null,
    _origin_center_x: bool = false,
    _origin_center_y: bool = false,
    relative: ?RelativeRef = null, // what to resolve against (Parent or NodeId)
    _callbacks: ?UIFramework.UIElementCallbacks = null,

    // ---- generic chainers (common Transform knobs) ----
    pub fn id(self: ElementChain, s: []const u8) ElementChain {
        var c = self;
        c._id = s;
        return c;
    }

    pub fn elId(self: ElementChain, elementIdentifier: UIElementIdentifier) ElementChain {
        var c = self;
        c.identifier = elementIdentifier;
        return c;
    }

    pub fn active(self: ElementChain, flag: bool) ElementChain {
        var c = self;
        c._active = flag;
        return c;
    }

    pub fn callbacks(self: ElementChain, cbs: UIFramework.UIElementCallbacks) ElementChain {
        var c = self;
        c._callbacks = cbs;
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

    pub fn positionRefX(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._positionRefX = r;
        return c;
    }

    pub fn positionRefY(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._positionRefY = r;
        return c;
    }

    pub fn sizeRef(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._sizeRef = r;
        return c;
    }

    pub fn sizeRefWidth(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._sizeRefWidth = r;
        return c;
    }

    pub fn sizeRefHeight(self: ElementChain, r: RelativeRef) ElementChain {
        var c = self;
        c._sizeRefHeight = r;
        return c;
    }

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

    pub fn relativeTransform(self: ElementChain, rt: *const Transform) ElementChain {
        var c = self;
        c._relativeTransform = rt;
        return c;
    }

    pub fn positionTransformX(self: ElementChain, rt: *const Transform) ElementChain {
        var c = self;
        c._positionTransformX = rt;
        return c;
    }

    pub fn positionTransformY(self: ElementChain, rt: *const Transform) ElementChain {
        var c = self;
        c._positionTransformY = rt;
        return c;
    }

    pub fn sizeTransformWidth(self: ElementChain, rt: *const Transform) ElementChain {
        var c = self;
        c._sizeTransformWidth = rt;
        return c;
    }

    pub fn sizeTransformHeight(self: ElementChain, rt: *const Transform) ElementChain {
        var c = self;
        c._sizeTransformHeight = rt;
        return c;
    }

    pub fn offsetToOrigin(self: ElementChain) ElementChain {
        var c = self;
        c._origin_center_x = true;
        c._origin_center_y = true;
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
        var me = self.el; // local copy
        const tr = UIElement.transformPtr(&me);

        switch (me) {
            inline else => |*el| {
                el.active = self._active;
                if (self.identifier) |elementId| el.identifier = elementId;
                if (self._callbacks) |cbs| el.callbacks = cbs;
            },
        }

        // Apply the explicit per-axis refs if provided.
        if (self._positionRef) |r| tr.position_ref = r;
        if (self._sizeRef) |r| tr.size_ref = r;
        if (self._positionRefX) |r| tr.position_ref_x = r;
        if (self._positionRefY) |r| tr.position_ref_y = r;
        if (self._sizeRefWidth) |r| tr.size_ref_width = r;
        if (self._sizeRefHeight) |r| tr.size_ref_height = r;
        if (self._relativeTransform) |rt| tr.relativeTransform = rt;
        if (self._positionTransformX) |rt| tr.position_transform_x = rt;
        if (self._positionTransformY) |rt| tr.position_transform_y = rt;
        if (self._sizeTransformWidth) |rt| tr.size_transform_width = rt;
        if (self._sizeTransformHeight) |rt| tr.size_transform_height = rt;
        if (self._origin_center_x) tr.origin_center_x = true;
        if (self._origin_center_y) tr.origin_center_y = true;

        // Leep 'relative' as a general fallback for 'both'
        if (self.relative) |r| tr.relative = r;

        // Add into parent with a sane default fallback
        const fallback_rel: RelativeRef =
            self._positionRef orelse
            self._positionRefX orelse
            self._positionRefY orelse
            self.relative orelse
            .Parent;
        if (self._id) |sid| {
            try parent.addChildNamed(sid, me, fallback_rel);
        } else if (self._positionRef) |r| {
            try parent.addChildWithRelative(me, r);
        } else if (self._positionRefX) |r| {
            try parent.addChildWithRelative(me, r);
        } else if (self._positionRefY) |r| {
            try parent.addChildWithRelative(me, r);
        } else if (self.relative) |r| {
            try parent.addChildWithRelative(me, r);
        } else {
            try parent.addChild(me, null); // defaults to parent pointer (safe)
        }
    }

    // ---- only valid if this ElementChain wraps a View ----
    pub fn children(self: ElementChain, kids: anytype) !View {
        var view_value: View = switch (self.el) {
            .View => |v| v,
            else => return error.ChildrenOnNonView,
        };

        // Don’t override pointer parent for .Parent
        if (self._relativeTransform) |rt| {
            view_value.transform.relativeTransform = rt;
        } else if (self.relative) |r| switch (r) {
            .NodeId => {
                view_value.transform.relativeTransform = null;
                view_value.transform.relative = r;
            },
            .Parent => {
                if (view_value.transform.relativeTransform == null) view_value.transform.relative = .Parent;
            },
        };

        if (self._positionRef) |r| view_value.transform.position_ref = r;
        if (self._sizeRef) |r| view_value.transform.size_ref = r;
        if (self._positionRefX) |r| view_value.transform.position_ref_x = r;
        if (self._positionRefY) |r| view_value.transform.position_ref_y = r;
        if (self._sizeRefWidth) |r| view_value.transform.size_ref_width = r;
        if (self._sizeRefHeight) |r| view_value.transform.size_ref_height = r;
        if (self._relativeTransform) |rt| view_value.transform.relativeTransform = rt;
        if (self._positionTransformX) |rt| view_value.transform.position_transform_x = rt;
        if (self._positionTransformY) |rt| view_value.transform.position_transform_y = rt;
        if (self._sizeTransformWidth) |rt| view_value.transform.size_transform_width = rt;
        if (self._sizeTransformHeight) |rt| view_value.transform.size_transform_height = rt;
        if (self._origin_center_x) view_value.transform.origin_center_x = true;
        if (self._origin_center_y) view_value.transform.origin_center_y = true;

        inline for (kids) |kid| try kid.buildInto(&view_value);
        return view_value;
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
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        position_ref: ?RelativeRef = null,
        position_ref_x: ?RelativeRef = null,
        position_ref_y: ?RelativeRef = null,
        size: SizeSpec = .{},
        size_ref: ?RelativeRef = null,
        size_ref_width: ?RelativeRef = null,
        size_ref_height: ?RelativeRef = null,
        relativeTransform: ?*const Transform = null,
        position_transform_x: ?*const Transform = null,
        position_transform_y: ?*const Transform = null,
        size_transform_width: ?*const Transform = null,
        size_transform_height: ?*const Transform = null,
        relative: ?RelativeRef = null,
        background: ?Rectangle = null,
    };

    pub fn view(self: UIChain, cfg: ViewConfig) ElementChain {
        var t: Transform = .{};
        t.position = cfg.position;
        t.position_ref = cfg.position_ref;
        t.position_ref_x = cfg.position_ref_x;
        t.position_ref_y = cfg.position_ref_y;
        t.size = cfg.size;
        t.size_ref = cfg.size_ref;
        t.size_ref_width = cfg.size_ref_width;
        t.size_ref_height = cfg.size_ref_height;
        t.relativeTransform = cfg.relativeTransform;
        t.position_transform_x = cfg.position_transform_x;
        t.position_transform_y = cfg.position_transform_y;
        t.size_transform_width = cfg.size_transform_width;
        t.size_transform_height = cfg.size_transform_height;
        t.relative = cfg.relative;
        t.offset_x = cfg.offset_x;
        t.offset_y = cfg.offset_y;
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

    pub fn rectangle(self: UIChain, config: Rectangle.Config) ElementChain {
        const rect = Rectangle.init(.{}, config);
        return .{ .allocator = self.allocator, .el = UIElement{ .Rectangle = rect } };
    }

    pub fn text(self: UIChain, value: [:0]const u8, config: Text.Config) ElementChain {
        const txt = Text.init(config.identifier, value, .{}, .{
            .font = config.font,
            .fontSize = config.fontSize,
            .spacing = config.spacing,
            .textColor = config.textColor,
        });
        return .{ .allocator = self.allocator, .el = UIElement{ .Text = txt } };
    }

    pub fn texture(self: UIChain, resource: anytype, config: Texture.Config) ElementChain {
        const tex = Texture.init(resource, .{}, null, config);
        return .{ .allocator = self.allocator, .el = UIElement{ .Texture = tex } };
    }

    pub fn textbox(self: UIChain, value: [:0]const u8, style: anytype, options: anytype) ElementChain {
        const tb = Textbox.init(self.allocator, value, .{}, style, options);
        return .{ .allocator = self.allocator, .el = UIElement{ .Textbox = tb } };
    }

    pub fn fileDropzone(self: UIChain, cfg: FileDropzone.Config) ElementChain {
        const dz = FileDropzone.init(cfg);
        return .{ .allocator = self.allocator, .el = UIElement{ .FileDropzone = dz } };
    }

    pub fn spriteButton(self: UIChain, cfg: SpriteButton.Config) ElementChain {
        const btn = SpriteButton.init(cfg);
        return .{ .allocator = self.allocator, .el = UIElement{ .SpriteButton = btn } };
    }

    pub fn deviceSelectBox(self: UIChain, cfg: DeviceSelectBox.Config) ElementChain {
        const box = DeviceSelectBox.init(cfg);
        return .{ .allocator = self.allocator, .el = UIElement{ .DeviceSelectBox = box } };
    }

    pub fn deviceSelectBoxList(self: UIChain, cfg: DeviceSelectBoxList.Config) ElementChain {
        const list = DeviceSelectBoxList.init(cfg);
        return .{ .allocator = self.allocator, .el = UIElement{ .DeviceSelectBoxList = list } };
    }

    pub fn progressBox(self: UIChain, cfg: ProgressBox.Config) ElementChain {
        const box = ProgressBox.init(cfg);
        return .{ .allocator = self.allocator, .el = UIElement{ .ProgressBox = box } };
    }
};
