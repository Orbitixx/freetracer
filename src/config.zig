// Main config file for app settings
pub const APP_VERSION = "1.0rc";
pub const PRIVILEGED_TOOL_LATEST_VERSION: [:0]const u8 = "1.0rc";

pub const DISK_PREFIX: []const u8 = "/dev/";

// Logs path in the Users/{USER} directory
pub const MAIN_APP_LOGS_PATH = "/freetracer.log";
// Preferences path in the Users/{USER} directory
pub const PREFERENCES_PATH = "/.config/freetracer/preferences.json";

// UpdateManager releases endpoint
pub const APP_RELEASES_API_ENDPOINT = "https://api.github.com/repos/orbitixx/freetracer/releases/latest";

// Max image file extension length
pub const MAX_EXT_LEN = 6;

pub const IMAGE_DISPLAY_NAME_BUFFER_LEN = 36;

pub const WINDOW_WIDTH_FACTOR: f32 = 0.49;
pub const WINDOW_HEIGHT_FACTOR: f32 = 0.52;
pub const WINDOW_FPS: i32 = 60;

pub const APP_UI_MODULE_PANEL_WIDTH_ACTIVE: f32 = 0.39; // 0.49
pub const APP_UI_MODULE_PANEL_WIDTH_INACTIVE: f32 = 0.22; // 0.16
pub const APP_UI_MODULE_PANEL_HEIGHT: f32 = 0.7;
pub const APP_UI_MODULE_PANEL_HEIGHT_ACTIVE: f32 = 0.7;
pub const APP_UI_MODULE_PANEL_HEIGHT_INACTIVE: f32 = 0.4;
pub const APP_UI_MODULE_PANEL_Y: f32 = 0.18;
pub const APP_UI_MODULE_PANEL_Y_INACTIVE: f32 = 0.55;
pub const APP_UI_MODULE_PANEL_FILE_PICKER_X: f32 = 0.06;
pub const APP_UI_MODULE_GAP_X: f32 = 20;
pub const APP_UI_MODULE_SECTION_PADDING: f32 = 0.1;
pub const APP_UI_MODULE_PADDING_LEFT: f32 = APP_UI_MODULE_SECTION_PADDING / 2;
pub const APP_UI_MODULE_PADDING_RIGHT: f32 = APP_UI_MODULE_PADDING_LEFT;
