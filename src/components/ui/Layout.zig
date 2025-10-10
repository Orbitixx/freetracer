const rl = @import("raylib");

const Primitives = @import("./Primitives.zig");
const Transform = Primitives.Transform;

pub const Axis = enum { horizontal, vertical };

pub const HorizontalAlign = enum { start, center, end };
pub const VerticalAlign = enum { start, center, end };

pub const CoordinateSpace = enum { relative, absolute };

pub const Space = struct {
    pub const none: f32 = 0;
    pub const xs: f32 = 4;
    pub const sm: f32 = 8;
    pub const md: f32 = 12;
    pub const lg: f32 = 16;
    pub const xl: f32 = 24;
    pub const twoXl: f32 = 32;
};

pub const Radius = struct {
    pub const none: f32 = 0;
    pub const sm: f32 = 4;
    pub const md: f32 = 8;
    pub const lg: f32 = 12;
    pub const pill: f32 = 999;
};

pub const Padding = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub fn uniform(value: f32) Padding {
        return .{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }

    pub fn symmetric(_horizontal: f32, _vertical: f32) Padding {
        return .{
            .top = _vertical,
            .right = _horizontal,
            .bottom = _vertical,
            .left = _horizontal,
        };
    }

    pub fn horizontal(value: f32) Padding {
        return .{
            .left = value,
            .right = value,
        };
    }

    pub fn vertical(value: f32) Padding {
        return .{
            .top = value,
            .bottom = value,
        };
    }

    pub fn add(self: Padding, other: Padding) Padding {
        return .{
            .top = self.top + other.top,
            .right = self.right + other.right,
            .bottom = self.bottom + other.bottom,
            .left = self.left + other.left,
        };
    }
};

pub const UnitValue = struct {
    perc: f32 = 0, // 0.0 - 1.0
    px: f32 = 0,

    pub fn pixels(value: f32) UnitValue {
        return .{ .px = value };
    }

    pub fn percent(value: f32) UnitValue {
        return .{ .perc = value };
    }

    pub fn mix(_percent: f32, _pixels: f32) UnitValue {
        return .{ .perc = _percent, .px = _pixels };
    }

    pub fn resolve(self: UnitValue, reference: f32) f32 {
        return reference * self.perc + self.px;
    }
};

pub const PositionSpec = struct {
    x: UnitValue = .{},
    y: UnitValue = .{},

    pub fn pixels(x: f32, y: f32) PositionSpec {
        return .{ .x = UnitValue.pixels(x), .y = UnitValue.pixels(y) };
    }

    pub fn percent(x: f32, y: f32) PositionSpec {
        return .{ .x = UnitValue.percent(x), .y = UnitValue.percent(y) };
    }

    pub fn mix(x: UnitValue, y: UnitValue) PositionSpec {
        return .{ .x = x, .y = y };
    }
};

pub const SizeSpec = struct {
    width: UnitValue = UnitValue.percent(1),
    height: UnitValue = UnitValue.percent(1),

    pub fn pixels(width: f32, height: f32) SizeSpec {
        return .{ .width = UnitValue.pixels(width), .height = UnitValue.pixels(height) };
    }

    pub fn percent(width: f32, height: f32) SizeSpec {
        return .{ .width = UnitValue.percent(width), .height = UnitValue.percent(height) };
    }

    pub fn mix(width: UnitValue, height: UnitValue) SizeSpec {
        return .{ .width = width, .height = height };
    }
};

pub const Bounds = struct {
    parent: ?*const Transform = null,
    position: PositionSpec = .{},
    size: SizeSpec = .{},
    space: CoordinateSpace = .relative,

    pub fn relative(parent: *const Transform, position: PositionSpec, size: SizeSpec) Bounds {
        return .{
            .parent = parent,
            .position = position,
            .size = size,
            .space = .relative,
        };
    }

    pub fn absolute(position: PositionSpec, size: SizeSpec, window: ?*const Transform) Bounds {
        return .{
            .parent = window,
            .position = position,
            .size = size,
            .space = .absolute,
        };
    }

    pub fn resolve(self: *const Bounds) Transform {
        const parent_transform: Transform = if (self.parent) |parent_ptr| parent_ptr.* else .{
            .x = 0,
            .y = 0,
            .w = 0,
            .h = 0,
            .scale = 1,
            .rotation = 0,
        };

        const reference_width: f32 = if (self.parent != null) parent_transform.w else 0;
        const reference_height: f32 = if (self.parent != null) parent_transform.h else 0;

        const resolved_width = @max(0, self.size.width.resolve(reference_width));
        const resolved_height = @max(0, self.size.height.resolve(reference_height));

        var offset_x = self.position.x.resolve(reference_width);
        var offset_y = self.position.y.resolve(reference_height);

        switch (self.space) {
            .relative => {
                offset_x = parent_transform.x + offset_x;
                offset_y = parent_transform.y + offset_y;
            },
            .absolute => {
                // absolute coordinates are relative to the window/viewport origin
                // but we still allow using parent size as a reference for percentages if provided.
            },
        }

        return .{
            .x = offset_x,
            .y = offset_y,
            .w = resolved_width,
            .h = resolved_height,
            .scale = parent_transform.scale,
            .rotation = 0,
        };
    }
};

pub fn applyPadding(area: Transform, padding: Padding) Transform {
    const width = @max(@as(f32, 0), area.w - (padding.left + padding.right));
    const height = @max(@as(f32, 0), area.h - (padding.top + padding.bottom));

    return .{
        .x = area.x + padding.left,
        .y = area.y + padding.top,
        .w = width,
        .h = height,
        .scale = area.scale,
        .rotation = area.rotation,
    };
}

pub fn inset(area: Transform, value: f32) Transform {
    return applyPadding(area, Padding.uniform(value));
}

pub fn alignWithin(area: Transform, size: rl.Vector2, horizontal: HorizontalAlign, vertical: VerticalAlign) rl.Vector2 {
    const x = switch (horizontal) {
        .start => area.x,
        .center => area.x + (area.w - size.x) / 2,
        .end => area.x + area.w - size.x,
    };

    const y = switch (vertical) {
        .start => area.y,
        .center => area.y + (area.h - size.y) / 2,
        .end => area.y + area.h - size.y,
    };

    return .{ .x = x, .y = y };
}

pub fn centerWithin(area: Transform, size: rl.Vector2) rl.Vector2 {
    return alignWithin(area, size, .center, .center);
}

pub fn centerTransform(area: Transform, child: Transform) Transform {
    const position = centerWithin(area, .{ .x = child.w, .y = child.h });

    return .{
        .x = position.x,
        .y = position.y,
        .w = child.w,
        .h = child.h,
        .scale = child.scale,
        .rotation = child.rotation,
    };
}

pub fn offset(position: rl.Vector2, delta: rl.Vector2) rl.Vector2 {
    return .{
        .x = position.x + delta.x,
        .y = position.y + delta.y,
    };
}

pub const RowBuilder = struct {
    content: Transform,
    spacing: f32 = 0,
    alignment: VerticalAlign = .center,
    cursor_x: f32,
    is_first_item: bool = true,

    pub fn init(area: Transform, padding: Padding, spacing: f32, alignment: VerticalAlign) RowBuilder {
        const content = applyPadding(area, padding);
        return .{
            .content = content,
            .spacing = spacing,
            .alignment = alignment,
            .cursor_x = content.x,
        };
    }

    pub fn place(self: *RowBuilder, size: rl.Vector2) rl.Vector2 {
        const x = if (self.is_first_item) self.cursor_x else self.cursor_x + self.spacing;

        const aligned_y = switch (self.alignment) {
            .start => self.content.y,
            .center => self.content.y + (self.content.h - size.y) / 2,
            .end => self.content.y + self.content.h - size.y,
        };

        const position = rl.Vector2{
            .x = x,
            .y = aligned_y,
        };

        self.cursor_x = position.x + size.x;
        self.is_first_item = false;

        return position;
    }
};

pub const ColumnBuilder = struct {
    content: Transform,
    spacing: f32 = 0,
    alignment: HorizontalAlign = .start,
    cursor_y: f32,
    is_first_item: bool = true,

    pub fn init(area: Transform, padding: Padding, spacing: f32, alignment: HorizontalAlign) ColumnBuilder {
        const content = applyPadding(area, padding);
        return .{
            .content = content,
            .spacing = spacing,
            .alignment = alignment,
            .cursor_y = content.y,
        };
    }

    pub fn place(self: *ColumnBuilder, size: rl.Vector2) rl.Vector2 {
        const y = if (self.is_first_item) self.cursor_y else self.cursor_y + self.spacing;

        const aligned_x = switch (self.alignment) {
            .start => self.content.x,
            .center => self.content.x + (self.content.w - size.x) / 2,
            .end => self.content.x + self.content.w - size.x,
        };

        const position = rl.Vector2{
            .x = aligned_x,
            .y = y,
        };

        self.cursor_y = position.y + size.y;
        self.is_first_item = false;

        return position;
    }
};

pub const LeadingIconText = struct {
    icon: rl.Vector2,
    text: rl.Vector2,
};

pub fn leadingIconText(area: Transform, iconSize: rl.Vector2, textSize: rl.Vector2, gap: f32, padding: Padding, alignment: VerticalAlign) LeadingIconText {
    const content = applyPadding(area, padding);

    const row_height = @max(iconSize.y, textSize.y);

    const y_start = switch (alignment) {
        .start => content.y,
        .center => content.y + (content.h - row_height) / 2,
        .end => content.y + content.h - row_height,
    };

    const icon_y = y_start + (row_height - iconSize.y) / 2;
    const text_y = y_start + (row_height - textSize.y) / 2;

    const icon_pos = rl.Vector2{
        .x = content.x,
        .y = icon_y,
    };

    const text_pos = rl.Vector2{
        .x = icon_pos.x + iconSize.x + gap,
        .y = text_y,
    };

    return .{
        .icon = icon_pos,
        .text = text_pos,
    };
}
