const rl = @import("raylib");

const Transform = @import("./Transform.zig");

const Styles = @import("../Styles.zig");
const TextStyle = Styles.TextStyle;
const RectangleStyle = Styles.RectangleStyle;

const Rectangle = @This();

transform: Transform,
rounded: bool = false,
bordered: bool = false,
style: RectangleStyle = .{},

pub fn draw(self: *Rectangle) void {
    //
    if (self.rounded) {
        self.drawRounded();
        return;
    }

    self.transform.resolve();

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

fn drawRounded(self: *Rectangle) void {
    self.transform.resolve();

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
