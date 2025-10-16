const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

pub const ResourceError = error{
    NoFontsLoadedError,
};

const FONTS_COUNT = std.meta.fields(FONT).len;
const TEXTURES_COUNT = std.meta.fields(TEXTURE).len;
const IMAGE_COUNT = std.meta.fields(IMAGE).len;
const SHADERS_COUNT = std.meta.fields(ShaderResource).len;

pub const FONT = enum(u8) { ROBOTO_REGULAR, JERSEY10_REGULAR };
pub const IMAGE = enum(u8) { APP_WINDOW_IMAGE };
pub const ShaderResource = enum(u8) { PIXELATE, SHADOW };

pub const TEXTURE = enum(u8) {
    DISK_IMAGE,
    USB_IMAGE,
    RELOAD_ICON,
    BUTTON_UI,
    DOC_IMAGE,
    STEP_1_INACTIVE,
    STAR_V1,
    STAR_V2,
    BUTTON_FRAME,
};

pub const Asset = union(enum) {
    Font: FONT,
    Image: IMAGE,
    Texture: TEXTURE,
    Shader: ShaderResource,
};

pub const Texture = rl.Texture2D;
pub const TextureResource = TEXTURE;

pub const ResourceManagerSingleton = struct {
    var allocator: std.mem.Allocator = undefined;
    var instance: ?ResourceManager = null;
    pub var defaultFont: rl.Font = undefined;
    pub var defaultTexture: rl.Texture2D = undefined;

    pub const ResourceManager = struct {
        allocator: std.mem.Allocator,
        fonts: []rl.Font,
        textures: []rl.Texture2D,
        images: []rl.Image,
        shaders: []rl.Shader,

        pub fn getFont(self: ResourceManager, font: FONT) rl.Font {
            // if (self.fonts.len < 1) return ResourceError.NoFontsLoaded;
            return self.fonts[@intFromEnum(font)];
        }

        pub fn getTexture(self: ResourceManager, texture: TEXTURE) rl.Texture2D {
            return self.textures[@intFromEnum(texture)];
        }

        pub fn getImage(self: ResourceManager, image: IMAGE) rl.Image {
            return self.images[@intFromEnum(image)];
        }

        pub fn getShader(self: ResourceManager, shader: ShaderResource) rl.Shader {
            return self.shaders[@intFromEnum(shader)];
        }

        fn registerAsset(self: ResourceManager, asset: Asset, fileName: []const u8) !void {
            const file = try getResourcePath(self.allocator, fileName);
            defer self.allocator.free(file);

            switch (asset) {
                .Font => |f| {
                    const font = try rl.loadFontEx(file, 64, null);
                    switch (f) {
                        .ROBOTO_REGULAR => rl.setTextureFilter(font.texture, .trilinear),
                        .JERSEY10_REGULAR => rl.setTextureFilter(font.texture, .point),
                    }
                    self.fonts[@intFromEnum(f)] = font;
                    if (f == .ROBOTO_REGULAR) ResourceManagerSingleton.defaultFont = font;
                },
                .Image => |i| self.images[@intFromEnum(i)] = try rl.loadImage(file),
                .Shader => |s| self.shaders[@intFromEnum(s)] = try rl.loadShader(null, file),
                .Texture => |t| {
                    const texture = try rl.loadTexture(file);
                    rl.setTextureFilter(texture, .point);
                    self.textures[@intFromEnum(t)] = texture;
                    if (t == .STAR_V2) ResourceManagerSingleton.defaultTexture = texture;
                },
            }
        }
    };

    pub fn init(_allocator: std.mem.Allocator) !void {
        allocator = _allocator;

        Debug.log(.DEBUG, "ResourceManager: started initialization...", .{});

        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);

        //--------------------------------------//
        //-------- *** LOAD FONTS *** ----------//
        //--------------------------------------//

        Debug.log(.DEBUG, "ResourceManager: preparing to load fonts...", .{});
        Debug.log(.DEBUG, "ResourceManager: preparing to load textures...", .{});

        //----------------------------------------//
        //-------- *** INITIALIZE INSTANCE *** ---//
        //----------------------------------------//

        instance = .{
            .allocator = allocator,
            .fonts = try allocator.alloc(rl.Font, FONTS_COUNT),
            .textures = try allocator.alloc(rl.Texture2D, TEXTURES_COUNT),
            .images = try allocator.alloc(rl.Image, IMAGE_COUNT),
            .shaders = try allocator.alloc(rl.Shader, SHADERS_COUNT),
        };

        if (instance) |*inst| {
            try inst.registerAsset(.{ .Font = .ROBOTO_REGULAR }, "fonts/Roboto-Regular.ttf");
            try inst.registerAsset(.{ .Font = .JERSEY10_REGULAR }, "fonts/Jersey10-Regular.ttf");
            Debug.log(.DEBUG, "ResourceManager: fonts successfully loaded!", .{});

            try inst.registerAsset(.{ .Texture = .DISK_IMAGE }, "images/disk_image.png");
            try inst.registerAsset(.{ .Texture = .USB_IMAGE }, "images/usb_image.png");
            try inst.registerAsset(.{ .Texture = .RELOAD_ICON }, "images/reload_icon.png");
            try inst.registerAsset(.{ .Texture = .BUTTON_UI }, "images/button_ui.png");
            try inst.registerAsset(.{ .Texture = .DOC_IMAGE }, "images/doc_image.png");
            try inst.registerAsset(.{ .Texture = .STEP_1_INACTIVE }, "images/step-1-inactive.png");
            try inst.registerAsset(.{ .Texture = .STAR_V1 }, "images/star_v1.png");
            try inst.registerAsset(.{ .Texture = .STAR_V2 }, "images/star_v2.png");
            try inst.registerAsset(.{ .Texture = .BUTTON_FRAME }, "images/button_frame.png");
            Debug.log(.DEBUG, "ResourceManager: textures successfully loaded!", .{});

            try inst.registerAsset(.{ .Image = .APP_WINDOW_IMAGE }, "images/icon.png");
            Debug.log(.DEBUG, "ResourceManager: images successfully loaded!", .{});

            try inst.registerAsset(.{ .Shader = .PIXELATE }, "shaders/pixelate.fs");
            try inst.registerAsset(.{ .Shader = .SHADOW }, "shaders/shadow.fs");
            Debug.log(.DEBUG, "ResourceManager: shaders successfully loaded!", .{});
        }

        Debug.log(.INFO, "ResourceManager: finished initialization!", .{});
    }

    // TODO: reworked back to unsafe/non-throwing method. To contemplate solution.
    // rl.getFontDefault() does not work on MacOS; throws error.LoadFont (zig-dev 5.6.0)
    pub fn getFont(font: FONT) rl.Font {
        return instance.?.getFont(font);
    }

    // TODO: reworked back to unsafe/non-throwing method. To contemplate solution.
    pub fn getTexture(texture: TextureResource) rl.Texture2D {
        return instance.?.getTexture(texture);
    }

    pub fn getImage(image: IMAGE) !rl.Image {
        return if (instance) |inst| inst.getImage(image) else error.UnableToGetImage;
    }

    pub fn getShader(shader: ShaderResource) !rl.Shader {
        return if (instance) |inst| inst.getShader(shader) else error.UnableToGetShader;
    }

    pub fn deinit() void {
        if (instance == null) {
            Debug.log(.ERROR, "ResourceManager deinit() called on an NULL instance.", .{});
            return;
        }

        for (instance.?.fonts) |font| {
            font.unload();
        }

        for (instance.?.textures) |texture| {
            texture.unload();
        }

        for (instance.?.images) |image| {
            image.unload();
        }

        for (instance.?.shaders) |shader| {
            shader.unload();
        }

        allocator.free(instance.?.fonts);
        allocator.free(instance.?.textures);
        allocator.free(instance.?.images);
        allocator.free(instance.?.shaders);

        instance = null;
    }
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
