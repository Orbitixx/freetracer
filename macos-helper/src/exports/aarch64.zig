const env = @import("../env.zig");

comptime {
    @export(
        @as([*:0]const u8, @ptrCast(env.INFO_PLIST)),
        .{
            .name = "__info_plist",
            .section = "__TEXT,__info_plist",
            .visibility = .default,
            .linkage = .strong,
        },
    );

    @export(
        @as([*:0]const u8, @ptrCast(env.LAUNCHD_PLIST)),
        .{
            .name = "__launchd_plist",
            .section = "__TEXT,__launchd_plist",
            .visibility = .default,
            .linkage = .strong,
        },
    );
}
