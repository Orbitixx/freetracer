const std = @import("std");
const debug = @import("../lib/util/debug.zig");
const rl = @import("raylib");

pub const ResourceManagerSingleton = struct {
    var allocator: std.mem.Allocator = undefined;
    var instance: ?ResourceManager = null;

    pub const ResourceManager = struct {
        allocator: std.mem.Allocator,
        fonts: []rl.Font,

        pub fn getFont(self: ResourceManager, font: FONT) rl.Font {
            // if (self.fonts.len < 1) return ResourceError.NoFontsLoaded;
            return self.fonts[@intFromEnum(font)];
        }
    };

    pub fn init(_allocator: std.mem.Allocator) !void {
        allocator = _allocator;

        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);

        const robotoFontFile = try std.fs.path.joinZ(allocator, &[_][]const u8{ cwd, "src/resources/Roboto-Regular.ttf" });
        defer allocator.free(robotoFontFile);

        debug.printf("Final file: {s}", .{robotoFontFile});

        const robotoRegular = try rl.loadFontEx(
            robotoFontFile,
            512,
            null,
        );

        instance = .{
            .allocator = allocator,
            .fonts = try allocator.alloc(rl.Font, 1),
        };

        instance.?.fonts[0] = robotoRegular;
    }

    pub fn getFont(font: FONT) rl.Font {
        return instance.?.getFont(font);
    }

    pub fn deinit() void {
        if (instance == null) {
            std.log.err("Error: ResourceManager deinit() called on an NULL instance.", .{});
            return;
        }

        for (instance.?.fonts) |font| {
            font.unload();
        }

        allocator.free(instance.?.fonts);

        instance = null;
    }
};

pub const ResourceError = error{
    NoFontsLoadedError,
};

pub const FONT = enum(usize) {
    ROBOTO_REGULAR = 0,
};
