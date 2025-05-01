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

        const robotoFontFile = try getResourcePath(allocator, "Roboto-Regular.ttf");
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

// TODO: Make a Linux adaptation
fn getResourcePath(allocator: std.mem.Allocator, resourceName: []const u8) ![:0]u8 {
    // On macOS, get the path to the executable
    const execPath = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(execPath);

    // For a .app bundle, the executable is typically in Contents/MacOS
    // and resources are in Contents/Resources
    const execDir = std.fs.path.dirname(execPath) orelse ".";

    // Check if we're in a .app bundle (Contents/MacOS directory)
    if (std.mem.endsWith(u8, execDir, "Contents/MacOS")) {
        // Navigate to Contents/Resources
        const resourcesDir = try std.fs.path.join(allocator, &[_][]const u8{
            execDir, "../Resources",
        });
        defer allocator.free(resourcesDir);

        // Join with the resource name
        return std.fs.path.joinZ(allocator, &[_][]const u8{
            resourcesDir, resourceName,
        });
    } else {
        // Fallback for development: try looking in src/resources relative to CWD
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);

        return std.fs.path.joinZ(allocator, &[_][]const u8{
            cwd, "src/resources", resourceName,
        });
    }
}
