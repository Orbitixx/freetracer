const env = @import("../env.zig");

export const __info_plist linksection("__TEXT,__info_plist") = env.INFO_PLIST.*;
export const __launchd_plist linksection("__TEXT,__launchd_plist") = env.LAUNCHD_PLIST.*;
