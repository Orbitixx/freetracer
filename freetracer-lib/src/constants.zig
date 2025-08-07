/// Collection of MacOS constants, imitating Apple's naming convention
/// of its own system framework constants
pub const k = struct {
    pub const MachPortPacketSize: comptime_int = 512;

    pub const HelperVersionRequest: i32 = 11;
    pub const UnmountDiskRequest: i32 = 101;
    pub const WriteISOToDeviceRequest: i32 = 102;

    pub const UnmountDiskResponse: i32 = 201;

    pub const SendTimeoutInSeconds: f64 = 5.0;
    pub const ReceiveTimeoutInSeconds: f64 = 5.0;

    pub const NullAuthorizationRights: @TypeOf(null) = null;
    pub const NullAuthorizationEnvironment: @TypeOf(null) = null;
    pub const NullAuthorizationItemValue: @TypeOf(null) = null;

    pub const EmptyAuthotizationFlags: u32 = 0;
    pub const EmptyAuthorizationItemFlags: u32 = 0;
    pub const ZeroAuthorizationItemValueLength: usize = 0;
};

pub const Character = struct {
    pub const NULL = 0x00;
    pub const SEMICOLON = 0x3b;
    pub const RIGHT_SLASH = 0x2f;
    pub const DOT = 0x2e;
};

pub const HelperRequestCode = enum(i64) {
    INITIAL_PING,
    GET_HELPER_VERSION,
    UNMOUNT_DISK,
    WRITE_ISO_TO_DEVICE,
};

pub const HelperResponseCode = enum(i64) {
    INITIAL_PONG,
    HELPER_VERSION_OBTAINED,

    DISK_UNMOUNT_SUCCESS,
    DISK_UNMOUNT_FAIL,

    ISO_FILE_INVALID,
    ISO_FILE_VALID,

    ISO_WRITE_PROGRESS,
    ISO_WRITE_SUCCESS,
    ISO_WRITE_FAIL,
};

pub const HelperReturnCode = enum(i32) {
    SUCCESS = 40,
    FAILED_TO_CREATE_DA_SESSION = 4000,
    FAILED_TO_CREATE_DA_DISK_REF = 4001,
    FAILED_TO_OBTAIN_DISK_INFO_DICT_REF = 4002,
    FAILED_TO_OBTAIN_EFI_KEY_STRING = 4003,
    FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL = 4004,
    UNMOUNT_REQUEST_ON_INTERNAL_DEVICE = 4005,
    SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION = 4006,
    MALFORMED_TARGET_DISK_STRING = 4007,

    FAILED_TO_WRITE_ISO_TO_DEVICE = 4100,
};

pub const HelperInstallCode = enum(u1) {
    FAILURE = 0,
    SUCCESS = 1,
};

pub const HelperUnmountRequestCode = enum(u2) {
    FAILURE = 0,
    SUCCESS = 1,
    TRY_AGAIN = 2,
};
//
// pub const HelperResponseCode = enum(u1) {
//     FAILURE = 0,
//     SUCCESS = 1,
// };
