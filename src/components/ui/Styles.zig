const rl = @import("raylib");
const ResourceManager = @import("../../managers/ResourceManager.zig");
const AppFont = ResourceManager.FONT;
const Texture = ResourceManager.Texture;

pub const Color = struct {
    pub const white = rl.Color.white;
    pub const offWhite = rl.Color{ .r = 190, .g = 190, .b = 190, .a = 255 };
    pub const black = rl.Color.black;
    pub const red = rl.Color.red;
    pub const green = rl.Color.green;
    pub const violet = rl.Color{ .r = 248, .g = 135, .b = 255, .a = 43 };
    pub const darkViolet = rl.Color{ .r = 248, .g = 135, .b = 255, .a = 20 };
    pub const blueGray = rl.Color{ .r = 49, .g = 85, .b = 100, .a = 255 };
    pub const darkBlueGray = rl.Color{ .r = 49, .g = 65, .b = 84, .a = 255 };
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
    disabled: ButtonStyle,
};

pub const CheckboxStyle = struct {
    outerRectStyle: RectangleStyle = .{},
    innerRectStyle: RectangleStyle = .{},
    textStyle: TextStyle = .{},
};

pub const CheckboxStyles = struct {
    normal: CheckboxStyle,
    hover: CheckboxStyle,
    checked: CheckboxStyle,
};

pub const StatusboxStyle = struct {
    outerRectStyle: RectangleStyle = .{},
    innerRectStyle: RectangleStyle = .{},
};

pub const StatusboxStyles = struct {
    none: StatusboxStyle,
    success: StatusboxStyle,
    failute: StatusboxStyle,
};
