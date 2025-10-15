const rl = @import("raylib");

const UIFramework = @import("./import.zig");
const Transform = UIFramework.Transform;
const UIEvent = UIFramework.UIEvent;

const Styles = @import("../Styles.zig");
const TextStyle = Styles.TextStyle;
const RectangleStyle = Styles.RectangleStyle;

pub const Config = struct {
    identifier: ?UIFramework.UIElementIdentifier = null,
    style: RectangleStyle = .{},
    rounded: bool = false,
    bordered: bool = false,
};

const Rectangle = @This();

transform: Transform,
rounded: bool = false,
bordered: bool = false,
style: RectangleStyle = .{},

pub fn init(transform: Transform, config: Config) Rectangle {
    return .{
        .transform = transform,
        .rounded = config.rounded,
        .bordered = config.bordered,
        .style = config.style,
    };
}

pub fn start(self: *Rectangle) !void {
    self.transform.resolve();
}

pub fn update(self: *Rectangle) !void {
    self.transform.resolve();
}

pub fn draw(self: *Rectangle) !void {
    //
    if (self.rounded) {
        self.drawRounded();
        return;
    }

    const bakedRect = rl.Rectangle{
        .x = self.transform.x,
        .y = self.transform.y,
        .width = self.transform.w,
        .height = self.transform.h,
    };

    rl.drawRectanglePro(
        bakedRect,
        .{ .x = 0, .y = 0 },
        self.transform.rotation,
        self.style.color,
    );

    if (self.bordered) {
        rl.drawRectangleLinesEx(
            bakedRect,
            self.style.borderStyle.thickness,
            self.style.borderStyle.color,
        );
    }
}

pub fn onEvent(self: *Rectangle, event: UIEvent) void {
    _ = self;
    _ = event;
}

fn drawRounded(self: *Rectangle) void {
    const bakedRect = rl.Rectangle{
        .x = self.transform.x,
        .y = self.transform.y,
        .width = self.transform.w,
        .height = self.transform.h,
    };

    rl.drawRectangleRounded(
        bakedRect,
        self.style.roundness,
        self.style.segments,
        self.style.color,
    );

    if (self.bordered) {
        rl.drawRectangleRoundedLinesEx(
            bakedRect,
            self.style.roundness,
            self.style.segments,
            self.style.borderStyle.thickness,
            self.style.borderStyle.color,
        );
    }

    return;
}

pub fn deinit(self: *Rectangle) void {
    _ = self;
}
