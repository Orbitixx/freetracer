const rl = @import("raylib");
const AppFont = @import("../../managers/ResourceManager.zig").FONT;

pub const Color = struct {
    pub const white = rl.Color.white;
    pub const black = rl.Color.black;
    pub const violet = rl.Color{ .r = 248, .g = 135, .b = 255, .a = 43 };
    pub const secondary = rl.Color{ .r = 78, .g = 96, .b = 121, .a = 255 };
    pub const transparent = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const transparentDark = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 60 };
    pub const lightGray = rl.Color.light_gray;
};

pub const TextStyle = struct {
    textColor: rl.Color = Color.white,
    font: AppFont = .ROBOTO_REGULAR,
    fontSize: f32 = 16,
    spacing: f32 = 0,
};

pub const BorderStyle = struct {
    color: rl.Color = Color.transparent,
    thickness: f32 = 2,
};

pub const RectangleStyle = struct {
    color: rl.Color = Color.transparent,
    borderStyle: BorderStyle = .{},
    roundness: f32 = 0.04,
    segments: i32 = 6,
};

pub const ButtonStyle = struct {
    bgStyle: RectangleStyle = .{},
    textStyle: TextStyle = .{},
};

pub const ButtonStyles = struct {
    normal: ButtonStyle,
    hover: ButtonStyle,
    active: ButtonStyle,
};
