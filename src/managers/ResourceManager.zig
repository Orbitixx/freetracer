const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

pub const ResourceError = error{
    NoFontsLoadedError,
};

const FONTS_COUNT: usize = 2;
const TEXTURES_COUNT: usize = 8;
const IMAGE_COUNT: usize = 1;

pub const FONT = enum(u8) {
    ROBOTO_REGULAR = 0,
    JERSEY10_REGULAR = 1,
};

pub const TEXTURE = enum(u8) {
    DISK_IMAGE = 0,
    USB_IMAGE = 1,
    RELOAD_ICON = 2,
    BUTTON_UI = 3,
    DOC_IMAGE = 4,
    STEP_1_INACTIVE = 5,
    STAR_V1 = 6,
    STAR_V2 = 7,
};

pub const IMAGE = enum(u8) {
    APP_WINDOW_IMAGE = 0,
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

        const robotoFontFile = try getResourcePath(allocator, "Roboto-Regular.ttf");
        defer allocator.free(robotoFontFile);

        const jerseyFontFile = try getResourcePath(allocator, "Jersey10-Regular.ttf");
        defer allocator.free(jerseyFontFile);

        const robotoRegular = try rl.loadFontEx(robotoFontFile, 32, null);
        rl.setTextureFilter(robotoRegular.texture, .trilinear);

        const jersey10Regular = try rl.loadFontEx(jerseyFontFile, 64, null);
        rl.setTextureFilter(jersey10Regular.texture, .point);

        Debug.log(.DEBUG, "ResourceManager: fonts successfully loaded!", .{});

        defaultFont = robotoRegular;

        //----------------------------------------//
        //-------- *** LOAD TEXTURES *** ---------//
        //----------------------------------------//

        Debug.log(.DEBUG, "ResourceManager: preparing to load textures...", .{});

        const diskTextureFile = try getResourcePath(allocator, "disk_image.png");
        defer allocator.free(diskTextureFile);
        const diskTexture = try rl.loadTexture(diskTextureFile);

        const docImageFile = try getResourcePath(allocator, "doc_image.png");
        defer allocator.free(docImageFile);
        const docImageTexture = try rl.loadTexture(docImageFile);

        const step1IFile = try getResourcePath(allocator, "step-1-inactive.png");
        defer allocator.free(step1IFile);
        const step1ITexture = try rl.loadTexture(step1IFile);

        const usbTextureFile = try getResourcePath(allocator, "usb_image.png");
        defer allocator.free(usbTextureFile);
        const usbTexture = try rl.loadTexture(usbTextureFile);

        const reloadIconTextureFile = try getResourcePath(allocator, "reload_icon.png");
        defer allocator.free(reloadIconTextureFile);
        const reloadIconTexture = try rl.loadTexture(reloadIconTextureFile);

        const buttonUiTextureFile = try getResourcePath(allocator, "button_ui.png");
        defer allocator.free(buttonUiTextureFile);
        const buttonUiTexture = try rl.loadTexture(buttonUiTextureFile);

        const starV1File = try getResourcePath(allocator, "star_v1.png");
        defer allocator.free(starV1File);
        const starV1Texture = try rl.loadTexture(starV1File);

        const starV2File = try getResourcePath(allocator, "star_v2.png");
        defer allocator.free(starV2File);
        const starV2Texture = try rl.loadTexture(starV2File);

        defaultTexture = starV2Texture;

        Debug.log(.DEBUG, "ResourceManager: textures successfully loaded!", .{});

        //----------------------------------------//
        //-------- *** INITIALIZE INSTANCE *** ---//
        //----------------------------------------//

        instance = .{
            .allocator = allocator,
            .fonts = try allocator.alloc(rl.Font, FONTS_COUNT),
            .textures = try allocator.alloc(rl.Texture2D, TEXTURES_COUNT),
            .images = try allocator.alloc(rl.Image, IMAGE_COUNT),
        };

        if (instance) |*inst| {
            inst.fonts[0] = robotoRegular;
            inst.fonts[1] = jersey10Regular;

            inst.textures[0] = diskTexture;
            inst.textures[1] = usbTexture;
            inst.textures[2] = reloadIconTexture;
            inst.textures[3] = buttonUiTexture;
            inst.textures[4] = docImageTexture;
            inst.textures[5] = step1ITexture;
            inst.textures[6] = starV1Texture;
            inst.textures[7] = starV2Texture;

            inst.images[@intFromEnum(IMAGE.APP_WINDOW_IMAGE)] = try registerImage(allocator, "icon.png");
        }

        Debug.log(.INFO, "ResourceManager: finished initialization!", .{});
    }

    // TODO: handle unhappy path
    pub fn getFont(font: FONT) !rl.Font {
        return if (instance) |inst| inst.getFont(font) else error.UnableToGetFont;
    }

    // TODO: handle unhappy path
    pub fn getTexture(texture: TextureResource) !rl.Texture2D {
        return if (instance) |inst| inst.getTexture(texture) else error.UnableToGetTexture;
    }

    pub fn getImage(image: IMAGE) !rl.Image {
        return if (instance) |inst| inst.getImage(image) else error.UnableToGetImage;
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

        allocator.free(instance.?.fonts);
        allocator.free(instance.?.textures);
        allocator.free(instance.?.images);

        // defaultFont.unload();
        // defaultTexture.unload();

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

fn registerImage(allocator: std.mem.Allocator, path: []const u8) !rl.Image {
    const imageFile = try getResourcePath(allocator, path);
    defer allocator.free(imageFile);
    return try rl.loadImage(imageFile);
}
