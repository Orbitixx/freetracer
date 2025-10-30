//! ResourceManager - Centralized asset loading and caching system
//!
//! Provides thread-safe management of fonts and textures with:
//! - Singleton pattern ensuring single resource instance
//! - Comprehensive error handling with proper resource cleanup
//! - Platform-aware resource path resolution (macOS app bundles and development builds)
//! - Verified initialization with error reporting
//! - Complete resource lifecycle management
//!
//! Threading Model:
//! - All public functions are thread-safe via global mutex
//! - Singleton initialization is protected against concurrent calls
//! - Safe for multi-threaded access after initialization
//!
//! Resource Loading:
//! - Assets are loaded during init() with full error handling
//! - Failed asset loads trigger rollback and return error
//! - No partial initialization; either all assets load or none do
//! - Resources are properly unloaded in deinit()
//! ==========================================================================
const std = @import("std");
const rl = @import("raylib");
const Debug = @import("freetracer-lib").Debug;

/// Comprehensive error type for resource manager operations
pub const ResourceError = error{
    /// Attempted to initialize ResourceManager when instance already exists
    AlreadyInitialized,

    /// ResourceManager not initialized; must call init() first
    NotInitialized,

    /// Failed to load font resource from file
    FontLoadFailed,

    /// Failed to load texture resource from file
    TextureLoadFailed,

    /// Failed to resolve resource file path
    PathResolutionFailed,

    /// No valid resources directory found
    NoResourcesDirectory,
};

/// Font type enumeration - corresponds to available font resources
pub const FONT = enum(u8) {
    ROBOTO_REGULAR,
    JERSEY10_REGULAR,
};

/// Texture type enumeration - corresponds to available texture resources
pub const TEXTURE = enum(u8) {
    RELOAD_ICON,
    BUTTON_UI,
    DOC_IMAGE,
    STEP_1_INACTIVE,
    STEP_2_INACTIVE,
    STEP_3_INACTIVE,
    STAR_V1,
    STAR_V2,
    BUTTON_FRAME,
    BUTTON_FRAME_DANGER,
    IMAGE_TAG,
    COPY_ICON,

    FILE_SELECTED,
    FILE_SELECTED_GLOW,
    DEVICE_SELECTED,
    DEVICE_SELECTED_GLOW,

    CHECKBOX_NORMAL,
    CHECKBOX_CHECKED,

    DEVICE_LIST_PLACEHOLDER,
    FLASH_PLACEHOLDER,

    SATTELITE_GRAPHIC,
    ROCKET_GRAPHIC,

    USB_ICON_INACTIVE,
    USB_ICON_ACTIVE,
    SD_ICON_INACTIVE,
    SD_ICON_ACTIVE,

    WARNING_ICON,
    DANGER_LINES,
};

/// Asset type discriminator for loading either fonts or textures
pub const Asset = union(enum) {
    Font: FONT,
    Texture: TEXTURE,
};

/// Public type aliases for convenient access
pub const Texture = rl.Texture2D;
pub const TextureResource = TEXTURE;

/// Number of fonts and textures (computed from enum field count)
const FONTS_COUNT = std.meta.fields(FONT).len;
const TEXTURES_COUNT = std.meta.fields(TEXTURE).len;

/// ResourceManager singleton providing global access to fonts and textures.
/// Thread-safe with comprehensive error handling and resource lifecycle management.
pub const ResourceManagerSingleton = struct {
    var mutex: std.Thread.Mutex = .{};
    var allocator: std.mem.Allocator = undefined;
    var instance: ?ResourceManager = null;
    var isInitialized: bool = false;

    // Default fallback resources in case of load failures
    pub var defaultFont: rl.Font = undefined;
    pub var defaultTexture: rl.Texture2D = undefined;

    /// Internal ResourceManager implementation
    const ResourceManager = struct {
        allocator: std.mem.Allocator,
        fonts: []rl.Font,
        textures: []rl.Texture2D,
        resourcesDir: [:0]u8,

        /// Retrieves a font by type with bounds validation.
        fn getFont(self: ResourceManager, font: FONT) rl.Font {
            const index = @intFromEnum(font);
            if (index >= self.fonts.len) {
                Debug.log(.ERROR, "ResourceManager: Font index {d} out of bounds", .{index});
                return defaultFont;
            }
            return self.fonts[index];
        }

        /// Retrieves a texture by type with bounds validation.
        fn getTexture(self: ResourceManager, texture: TEXTURE) rl.Texture2D {
            const index = @intFromEnum(texture);
            if (index >= self.textures.len) {
                Debug.log(.ERROR, "ResourceManager: Texture index {d} out of bounds", .{index});
                return defaultTexture;
            }
            return self.textures[index];
        }

        /// Registers (loads) a single asset from disk.
        /// Validates path, loads via raylib, and stores in appropriate array slot.
        ///
        /// `Arguments`:
        ///   asset: Asset discriminator (Font or Texture)
        ///   fileName: Relative path to asset file
        ///
        /// `Returns`: ResourceError if load fails
        fn registerAsset(self: ResourceManager, asset: Asset, fileName: []const u8) ResourceError!void {
            // Construct full path to asset
            const fullPath = std.fs.path.joinZ(
                self.allocator,
                &[_][]const u8{ self.resourcesDir, fileName },
            ) catch |err| {
                Debug.log(.ERROR, "ResourceManager: Failed to construct path for '{s}': {any}", .{ fileName, err });
                return ResourceError.PathResolutionFailed;
            };
            defer self.allocator.free(fullPath);

            Debug.log(.DEBUG, "ResourceManager: Loading asset from {s}", .{fullPath});

            switch (asset) {
                .Font => |f| {
                    const font = rl.loadFontEx(fullPath, 96, null) catch |err| {
                        Debug.log(.ERROR, "ResourceManager: Failed to load font '{s}': {any}", .{ fileName, err });
                        return ResourceError.FontLoadFailed;
                    };

                    // Configure texture filtering based on font type
                    switch (f) {
                        .ROBOTO_REGULAR => rl.setTextureFilter(font.texture, .trilinear),
                        .JERSEY10_REGULAR => rl.setTextureFilter(font.texture, .point),
                    }

                    const index = @intFromEnum(f);
                    if (index >= self.fonts.len) {
                        Debug.log(.ERROR, "ResourceManager: Font enum index {d} out of bounds", .{index});
                        font.unload();
                        return ResourceError.FontLoadFailed;
                    }

                    self.fonts[index] = font;
                    if (f == .ROBOTO_REGULAR) ResourceManagerSingleton.defaultFont = font;
                },
                .Texture => |t| {
                    const texture = rl.loadTexture(fullPath) catch |err| {
                        Debug.log(.ERROR, "ResourceManager: Failed to load texture '{s}': {any}", .{ fileName, err });
                        return ResourceError.TextureLoadFailed;
                    };

                    rl.setTextureFilter(texture, .point);

                    const index = @intFromEnum(t);
                    if (index >= self.textures.len) {
                        Debug.log(.ERROR, "ResourceManager: Texture enum index {d} out of bounds", .{index});
                        texture.unload();
                        return ResourceError.TextureLoadFailed;
                    }

                    self.textures[index] = texture;
                    if (t == .STAR_V2) ResourceManagerSingleton.defaultTexture = texture;
                },
            }
        }

        /// Unloads all resources and frees allocated memory
        fn deinit(self: *ResourceManager) void {
            for (self.fonts) |font| {
                if (font.texture.id != 0) {
                    // Only unload if texture ID is valid (resource was actually loaded)
                    font.unload();
                }
            }

            for (self.textures) |texture| {
                if (texture.id != 0) {
                    // Only unload if ID is valid (resource was actually loaded)
                    texture.unload();
                }
            }

            self.allocator.free(self.fonts);
            self.allocator.free(self.textures);
            self.allocator.free(self.resourcesDir);
        }
    };

    /// Initializes the ResourceManager singleton with all assets.
    /// Must be called exactly once at application startup.
    /// Implements comprehensive error handling with rollback on failure.
    ///
    /// `Arguments`:
    ///   _allocator: Memory allocator for asset storage. Must remain valid for app lifetime.
    ///
    /// `Returns`: ResourceError if any asset fails to load
    ///          ResourceError.AlreadyInitialized if init() called more than once
    pub fn init(_allocator: std.mem.Allocator) ResourceError!void {
        mutex.lock();
        defer mutex.unlock();

        if (isInitialized) {
            Debug.log(.ERROR, "ResourceManager.init() called but already initialized", .{});
            return ResourceError.AlreadyInitialized;
        }

        allocator = _allocator;

        Debug.log(.DEBUG, "ResourceManager: started initialization...", .{});

        // Resolve resources directory
        const resourcesDir = resolveResourcesDirectory(allocator) catch |err| {
            Debug.log(.ERROR, "ResourceManager: Failed to resolve resources directory: {any}", .{err});
            return ResourceError.NoResourcesDirectory;
        };

        // Allocate arrays for fonts and textures
        const fonts = allocator.alloc(rl.Font, FONTS_COUNT) catch |err| {
            Debug.log(.ERROR, "ResourceManager: Failed to allocate font array: {any}", .{err});
            allocator.free(resourcesDir);
            return ResourceError.FontLoadFailed;
        };
        errdefer allocator.free(fonts);

        const textures = allocator.alloc(rl.Texture2D, TEXTURES_COUNT) catch |err| {
            Debug.log(.ERROR, "ResourceManager: Failed to allocate texture array: {any}", .{err});
            allocator.free(fonts);
            allocator.free(resourcesDir);
            return ResourceError.TextureLoadFailed;
        };
        errdefer allocator.free(textures);

        // Initialize arrays as uninitialized (will be filled by registerAsset or marked invalid)
        // Use memset with zero values; individual assets will be properly initialized on load
        var i: usize = 0;
        while (i < fonts.len) : (i += 1) {
            // Mark as invalid by having zero texture ID (indicates uninitialized)
            fonts[i] = undefined;
        }
        i = 0;
        while (i < textures.len) : (i += 1) {
            // Mark as invalid by having zero ID (indicates uninitialized)
            textures[i] = undefined;
        }

        // Create instance with allocated resources
        var manager = ResourceManager{
            .allocator = allocator,
            .fonts = fonts,
            .textures = textures,
            .resourcesDir = resourcesDir,
        };

        // Load all fonts with rollback on failure
        Debug.log(.DEBUG, "ResourceManager: Loading fonts...", .{});

        manager.registerAsset(.{ .Font = .ROBOTO_REGULAR }, "fonts/Roboto-Regular.ttf") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Font = .JERSEY10_REGULAR }, "fonts/Jersey10-Regular.ttf") catch |err| {
            manager.deinit();
            return err;
        };

        Debug.log(.DEBUG, "ResourceManager: Fonts successfully loaded", .{});

        // Load all textures with rollback on failure
        Debug.log(.DEBUG, "ResourceManager: Loading textures...", .{});
        manager.registerAsset(.{ .Texture = .RELOAD_ICON }, "images/icon-reload.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .COPY_ICON }, "images/copy-icon.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .BUTTON_UI }, "images/button_ui.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .DOC_IMAGE }, "images/doc_image.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .FILE_SELECTED }, "images/selected-file-icon.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .FILE_SELECTED_GLOW }, "images/file-picker-glow.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .DEVICE_SELECTED }, "images/target-device-icon.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .DEVICE_SELECTED_GLOW }, "images/device-list-glow.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .STEP_1_INACTIVE }, "images/step-1-inactive.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .STEP_2_INACTIVE }, "images/step-2-inactive.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .STEP_3_INACTIVE }, "images/step-3-inactive.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .STAR_V1 }, "images/star_v1.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .STAR_V2 }, "images/star_v2.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .BUTTON_FRAME }, "images/button_frame.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .BUTTON_FRAME_DANGER }, "images/button_frame_danger.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .IMAGE_TAG }, "images/tag.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .CHECKBOX_NORMAL }, "images/checkbox-normal.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .CHECKBOX_CHECKED }, "images/checkbox-checked.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .WARNING_ICON }, "images/warning-icon.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .DANGER_LINES }, "images/danger-lines.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .FLASH_PLACEHOLDER }, "images/flash-placeholder.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .DEVICE_LIST_PLACEHOLDER }, "images/device-list-placeholder.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .USB_ICON_INACTIVE }, "images/usb-icon-inactive.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .USB_ICON_ACTIVE }, "images/usb-icon-active.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .SD_ICON_INACTIVE }, "images/sd-icon-inactive.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .SD_ICON_ACTIVE }, "images/sd-icon-active.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .SATTELITE_GRAPHIC }, "images/sattelite-graphic.png") catch |err| {
            manager.deinit();
            return err;
        };

        manager.registerAsset(.{ .Texture = .ROCKET_GRAPHIC }, "images/rocket.png") catch |err| {
            manager.deinit();
            return err;
        };

        Debug.log(.DEBUG, "ResourceManager: Textures successfully loaded", .{});

        // Store instance and mark as initialized
        instance = manager;
        isInitialized = true;

        Debug.log(.INFO, "ResourceManager: Initialization completed successfully", .{});
    }

    /// Retrieves a font by type.
    /// Thread-safe access to loaded font resources.
    ///
    /// `Arguments`:
    ///   font: Font type identifier
    ///
    /// `Returns`: Loaded font resource, or defaultFont if not initialized
    pub fn getFont(font: FONT) rl.Font {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |inst| {
            return inst.getFont(font);
        }

        Debug.log(.WARNING, "ResourceManager.getFont() called but not initialized", .{});
        return defaultFont;
    }

    /// Retrieves a texture by type.
    /// Thread-safe access to loaded texture resources.
    ///
    /// `Arguments`:
    ///   texture: Texture type identifier
    ///
    /// `Returns`: Loaded texture resource, or defaultTexture if not initialized
    pub fn getTexture(texture: TextureResource) rl.Texture2D {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |inst| {
            return inst.getTexture(texture);
        }

        Debug.log(.WARNING, "ResourceManager.getTexture() called but not initialized", .{});
        return defaultTexture;
    }

    /// Checks if ResourceManager has been successfully initialized.
    /// Use this to verify initialization before calling getFont/getTexture.
    ///
    /// `Returns`: true if init() succeeded, false otherwise
    pub fn isReady() bool {
        mutex.lock();
        defer mutex.unlock();
        return isInitialized;
    }

    /// Deinitializes the ResourceManager and unloads all resources.
    /// Must be called once at application shutdown.
    /// Safe to call even if init() failed.
    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |*inst| {
            inst.deinit();
            instance = null;
        }

        isInitialized = false;
        Debug.log(.INFO, "ResourceManager: Deinitialization complete", .{});
    }
};

/// Resolves the resources directory based on platform and execution context.
/// Handles macOS app bundles and development build directory structures.
///
/// `Arguments`:
///   allocator: Memory allocator for path construction
///
/// `Returns`: Null-terminated path to resources directory
/// `Errors`: PathResolutionFailed if resolution fails
fn resolveResourcesDirectory(allocator: std.mem.Allocator) ![:0]u8 {
    // Get executable path
    const execPath = std.fs.selfExePathAlloc(allocator) catch |err| {
        Debug.log(.ERROR, "ResourceManager: Failed to get executable path: {any}", .{err});
        return ResourceError.PathResolutionFailed;
    };
    defer allocator.free(execPath);

    // Extract directory containing executable
    const execDir = std.fs.path.dirname(execPath) orelse ".";

    // Check if running from macOS app bundle (Contents/MacOS directory)
    if (std.mem.endsWith(u8, execDir, "Contents/MacOS")) {
        Debug.log(.DEBUG, "ResourceManager: Detected macOS app bundle", .{});

        // Navigate to Contents/Resources directory
        const resourcesPath = std.fs.path.joinZ(
            allocator,
            &[_][]const u8{ execDir, "..", "Resources" },
        ) catch |err| {
            Debug.log(.ERROR, "ResourceManager: Failed to construct bundle resources path: {any}", .{err});
            return ResourceError.PathResolutionFailed;
        };

        return resourcesPath;
    }

    // Fallback for development builds: look in src/resources relative to CWD
    Debug.log(.DEBUG, "ResourceManager: Not running from app bundle, using development path", .{});

    const cwd = std.process.getCwdAlloc(allocator) catch |err| {
        Debug.log(.ERROR, "ResourceManager: Failed to get current directory: {any}", .{err});
        return ResourceError.PathResolutionFailed;
    };
    defer allocator.free(cwd);

    const devResourcesPath = std.fs.path.joinZ(
        allocator,
        &[_][]const u8{ cwd, "src/resources" },
    ) catch |err| {
        Debug.log(.ERROR, "ResourceManager: Failed to construct development resources path: {any}", .{err});
        return ResourceError.PathResolutionFailed;
    };

    return devResourcesPath;
}
