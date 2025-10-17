// Main config file for app settings

pub const APP_VERSION = "0.9";
pub const PRIVILEGED_TOOL_LATEST_VERSION: [:0]const u8 = "0.9";

pub const DISK_PREFIX: []const u8 = "/dev/";

// Logs path in the Users/{USER} directory
pub const MAIN_APP_LOGS_PATH = "/freetracer.log";
pub const ALLOWED_IMAGE_EXTENSIONS = [_][]const u8{ ".iso", ".img" };
pub const MAX_EXT_LEN = 6;

pub const IMAGE_DISPLAY_NAME_BUFFER_LEN = 36;

pub const WINDOW_WIDTH_FACTOR: f32 = 0.5;
pub const WINDOW_HEIGHT_FACTOR: f32 = 0.52;
pub const WINDOW_FPS: i32 = 60;

pub const APP_UI_MODULE_PANEL_WIDTH_ACTIVE: f32 = 0.40; // 0.49
pub const APP_UI_MODULE_PANEL_WIDTH_INACTIVE: f32 = 0.20; // 0.16
pub const APP_UI_MODULE_PANEL_HEIGHT: f32 = 0.7;
pub const APP_UI_MODULE_PANEL_HEIGHT_ACTIVE: f32 = 0.7;
pub const APP_UI_MODULE_PANEL_HEIGHT_INACTIVE: f32 = 0.45;
pub const APP_UI_MODULE_PANEL_Y: f32 = 0.18;
pub const APP_UI_MODULE_PANEL_Y_INACTIVE: f32 = 0.28;
pub const APP_UI_MODULE_PANEL_FILE_PICKER_X: f32 = 0.08;
pub const APP_UI_MODULE_GAP_X: f32 = 20;

pub const CHECKBOX_TEXT_MARGIN_LEFT: f32 = 12;
pub const CHECKBOX_TEXT_BUFFER_SIZE: usize = 60;

pub const DEVICE_CHECKBOXES_GAP_FACTOR_Y: f32 = 30;

// DataFlasherUI
pub const APP_UI_MODULE_SECTION_PADDING: f32 = 0.1;
pub const APP_UI_MODULE_PADDING_LEFT: f32 = APP_UI_MODULE_SECTION_PADDING / 2;
pub const APP_UI_MODULE_PADDING_RIGHT: f32 = APP_UI_MODULE_PADDING_LEFT;

pub const HEADER_LABEL_OFFSET_X: f32 = 12.0;
pub const HEADER_LABEL_REL_Y: f32 = 0.01;
pub const FLASH_BUTTON_REL_Y: f32 = 0.9;

pub const TEXTURE_TILE_SIZE = 16;

pub const ICON_SIZE = 22;
pub const ICON_TEXT_GAP_X = ICON_SIZE * 1.5;
pub const ISO_ICON_POS_REL_X = APP_UI_MODULE_PADDING_LEFT;
pub const ISO_ICON_POS_REL_Y = APP_UI_MODULE_SECTION_PADDING;
pub const DEV_ICON_POS_REL_X = ISO_ICON_POS_REL_X;
pub const DEV_ICON_POS_REL_Y = ISO_ICON_POS_REL_Y + ISO_ICON_POS_REL_Y / 2;

pub const ITEM_GAP_Y = 8;
pub const STATUS_INDICATOR_SIZE: f32 = 20;
