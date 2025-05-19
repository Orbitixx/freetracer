const std = @import("std");
const debug = @import("../lib/util/debug.zig");
const rl = @import("raylib");

pub const ResourceManagerSingleton = struct {
    var allocator: std.mem.Allocator = undefined;
    var instance: ?ResourceManager = null;

    pub const ResourceManager = struct {
        allocator: std.mem.Allocator,
        fonts: []rl.Font,
        textures: []rl.Texture2D,

        pub fn getFont(self: ResourceManager, font: FONT) rl.Font {
            // if (self.fonts.len < 1) return ResourceError.NoFontsLoaded;
            return self.fonts[@intFromEnum(font)];
        }

        pub fn getTexture(self: ResourceManager, texture: TEXTURE) rl.Texture2D {
            return self.textures[@intFromEnum(texture)];
        }
    };

    pub fn init(_allocator: std.mem.Allocator) !void {
        allocator = _allocator;

        debug.print("\nResourceManager: started initialization...");

        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);

        //--------------------------------------//
        //-------- *** LOAD FONTS *** ----------//
        //--------------------------------------//

        debug.print("\nResourceManager: preparing to load fonts...");

        const robotoFontFile = try getResourcePath(allocator, "Roboto-Regular.ttf");
        defer allocator.free(robotoFontFile);

        const jerseyFontFile = try getResourcePath(allocator, "Jersey10-Regular.ttf");
        defer allocator.free(jerseyFontFile);

        const robotoRegular = try rl.loadFontEx(robotoFontFile, 512, null);
        rl.setTextureFilter(robotoRegular.texture, .trilinear);

        const jersey10Regular = try rl.loadFontEx(jerseyFontFile, 512, null);
        rl.setTextureFilter(jersey10Regular.texture, .trilinear);

        debug.print("\nResourceManager: fonts successfully loaded!");

        //----------------------------------------//
        //-------- *** LOAD TEXTURES *** ---------//
        //----------------------------------------//

        debug.print("\nResourceManager: preparing to load textures...");

        const diskTextureFile = try getResourcePath(allocator, "disk_image.png");
        defer allocator.free(diskTextureFile);

        const diskTexture = try rl.loadTexture(diskTextureFile);

        debug.print("\nResourceManager: textures successfully loaded!");

        //----------------------------------------//
        //-------- *** INITIALIZE INSTANCE *** ---//
        //----------------------------------------//

        instance = .{
            .allocator = allocator,
            .fonts = try allocator.alloc(rl.Font, 2),
            .textures = try allocator.alloc(rl.Texture2D, 1),
        };

        if (instance) |*inst| {
            inst.fonts[0] = robotoRegular;
            inst.fonts[1] = jersey10Regular;
            inst.textures[0] = diskTexture;
        }

        debug.print("\nResourceManager: finished initialization!");
    }

    // TODO: handle unhappy path
    pub fn getFont(font: FONT) rl.Font {
        return instance.?.getFont(font);
    }

    // TODO: handle unhappy path
    pub fn getTexture(texture: TEXTURE) rl.Texture2D {
        return instance.?.getTexture(texture);
    }

    pub fn deinit() void {
        if (instance == null) {
            std.log.err("Error: ResourceManager deinit() called on an NULL instance.", .{});
            return;
        }

        for (instance.?.fonts) |font| {
            font.unload();
        }

        for (instance.?.textures) |texture| {
            texture.unload();
        }

        allocator.free(instance.?.fonts);
        allocator.free(instance.?.textures);

        instance = null;
    }
};

pub const ResourceError = error{
    NoFontsLoadedError,
};

pub const FONT = enum(u8) {
    ROBOTO_REGULAR = 0,
    JERSEY10_REGULAR = 1,
};

pub const TEXTURE = enum(u8) {
    DISK_IMAGE = 0,
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
