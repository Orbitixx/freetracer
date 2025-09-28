// Main config file for app settings

pub const APP_VERSION = "v0.2";
pub const PRIVILEGED_TOOL_LATEST_VERSION: [:0]const u8 = "0.1.7";

pub const DISK_PREFIX: []const u8 = "/dev/";

// Logs path in the Users/{USER} directory
pub const MAIN_APP_LOGS_PATH = "/freetracer.log";

pub const WINDOW_WIDTH_FACTOR: f32 = 0.5;
pub const WINDOW_HEIGHT_FACTOR: f32 = 0.54;
pub const WINDOW_FPS: i32 = 30;

pub const APP_UI_MODULE_PANEL_WIDTH_ACTIVE: f32 = 0.49;
pub const APP_UI_MODULE_PANEL_WIDTH_INACTIVE: f32 = 0.16;
pub const APP_UI_MODULE_PANEL_HEIGHT: f32 = 0.75;
pub const APP_UI_MODULE_PANEL_Y: f32 = 0.18;
pub const APP_UI_MODULE_PANEL_FILE_PICKER_X: f32 = 0.08;

pub const CHECKBOX_TEXT_MARGIN_LEFT: f32 = 12;
pub const CHECKBOX_TEXT_BUFFER_SIZE: usize = 60;
