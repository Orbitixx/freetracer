/// Collection of MacOS constants, imitating Apple's naming convention
/// of its own system framework constants
pub const k = struct {
    pub const HelperVersionRequest: i32 = 11;
    pub const UnmountDiskRequest: i32 = 101;
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

pub const HelperReturnCode = enum(i32) {
    SUCCESS = 40,
    FAILED_TO_CREATE_DA_SESSION = 4000,
    FAILED_TO_CREATE_DA_DISK_REF = 4001,
    FAILED_TO_OBTAIN_DISK_INFO_DICT_REF = 4002,
    FAILED_TO_OBTAIN_EFI_KEY_STRING = 4003,
    FAILED_TO_OBTAIN_INTERNAL_DEVICE_KEY_BOOL = 4004,
    UNMOUNT_REQUEST_ON_INTERNAL_DEVICE = 4005,
    SKIPPED_UNMOUNT_ATTEMPT_ON_EFI_PARTITION = 4006,
};

pub const HelperInstallCode = enum(u1) {
    FAILURE = 0,
    SUCCESS = 1,
};

pub const HelperUnmountRequestCode = enum(u1) {
    FAILURE = 0,
    SUCCESS = 1,
};

pub const HelperResponseCode = enum(u1) {
    FAILURE = 0,
    SUCCESS = 1,
};
