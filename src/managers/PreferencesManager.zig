const std = @import("std");
const osd = @import("osdialog");
const json = std.json;

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const SeverityLevel = freetracer_lib.Debug.SeverityLevel;

/// Maximum preferences file size to prevent DoS via malicious/corrupted files (1 MB)
const MAX_PREFERENCES_FILE_SIZE = 1024 * 1024;

/// Maximum recursion depth for persist() file creation attempts
const MAX_PERSIST_RECURSION_DEPTH = 3;

/// Comprehensive error type for preferences manager operations.
/// Distinguishes between initialization failures, I/O errors, and validation errors.
pub const PreferenceError = error{
    /// Attempted to initialize preferences manager when instance already exists
    AlreadyInitialized,

    /// Preferences manager not initialized; must call init() first
    NotInitialized,

    /// I/O operation failed (file read, write, or permission error)
    IoFailure,

    /// Provided path exceeds maximum path length
    PathTooLong,

    /// Path contains invalid characters or attempts directory traversal
    InvalidPath,

    /// File size exceeds maximum allowed size limit
    FileSizeExceeded,

    /// Recursive persist() exceeded maximum depth (possible permission loop)
    MaxPersistDepthExceeded,

    /// JSON contains invalid enum values or malformed data
    InvalidPreferences,
};

/// Enumeration of supported preference keys that can be persisted
pub const PreferenceKey = enum {
    CheckUpdates,
    DebugLevel,
    ForceHelperInstall,
};

/// Default values for all preferences
const Defaults = struct {
    pub const checkUpdates = false;
    pub const debugLevel = SeverityLevel.DEBUG;
    pub const forceHelperInstall = false;
};

/// In-memory representation of user preferences
const Preferences = struct {
    checkUpdates: bool = Defaults.checkUpdates,
    debugLevel: SeverityLevel = Defaults.debugLevel,
    forceHelperInstall: bool = Defaults.forceHelperInstall,
};

/// JSON-serializable representation of preferences file payload.
/// All fields are optional to support partial deserialization and forward compatibility.
const FilePayload = struct {
    checkUpdates: ?bool = null,
    debugLevel: ?u8 = null,
    forceHelperInstall: ?bool = null,
};

/// PreferencesManager maintains user settings and persists them to disk.
///
/// Implementation notes:
/// - Uses a fixed-size path buffer to avoid allocations
/// - Lazy-creates preferences file on first load
/// - Validates enum ranges when deserializing from JSON
/// - Thread-safe via global mutex
/// - Singleton pattern ensures single instance throughout app lifetime
const PreferencesManager = struct {
    allocator: std.mem.Allocator,
    data: Preferences = .{},
    pathBuffer: [std.fs.max_path_bytes]u8 = undefined,
    pathLen: usize = 0,
    isFirstLaunch: bool = false,
    persistDepth: u32 = 0,

    /// Returns the null-terminated preference file path
    fn getPath(self: *const PreferencesManager) [:0]const u8 {
        return self.pathBuffer[0..self.pathLen :0];
    }

    /// Initializes the preferences manager with the given allocator and file path.
    /// Validates the path and loads or creates the preferences file.
    ///
    /// Arguments:
    ///   allocator: Memory allocator for temporary allocations
    ///   path: Absolute path to preferences file (must be null-terminated)
    ///
    /// Returns: PreferenceError.PathTooLong if path exceeds buffer
    ///          PreferenceError.InvalidPath if path contains invalid characters
    ///          PreferenceError.IoFailure if file I/O fails
    fn init(allocator: std.mem.Allocator, path: [:0]const u8) !PreferencesManager {
        var manager = PreferencesManager{
            .allocator = allocator,
        };

        // Validate and store path
        if (path.len >= manager.pathBuffer.len) {
            return PreferenceError.PathTooLong;
        }

        // Basic path validation: check for directory traversal attempts
        if (std.mem.containsAtLeast(u8, path, 1, "..")) {
            Debug.log(.ERROR, "PreferencesManager: Path contains directory traversal sequence", .{});
            return PreferenceError.InvalidPath;
        }

        @memcpy(manager.pathBuffer[0..path.len], path);
        manager.pathBuffer[path.len] = 0;
        manager.pathLen = path.len;

        try manager.loadOrCreate();

        return manager;
    }

    /// Loads existing preferences from file, or creates a new preferences file with defaults.
    /// If file is empty or malformed, reverts to defaults and persists.
    ///
    /// Returns: PreferenceError.IoFailure if file I/O fails
    ///          PreferenceError.FileSizeExceeded if file size exceeds limit
    ///          PreferenceError.InvalidPreferences if JSON is malformed
    fn loadOrCreate(self: *PreferencesManager) !void {
        self.data = .{};
        try self.ensureDirectoryExists();

        const file = std.fs.openFileAbsolute(self.getPath(), .{ .mode = .read_only }) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                self.isFirstLaunch = true;
                try self.persist();
                return;
            },
            else => {
                Debug.log(.ERROR, "PreferencesManager: Failed to open preferences file: {any}", .{err});
                return PreferenceError.IoFailure;
            },
        };
        defer file.close();

        // Get file size and validate against maximum
        const fileSize = try file.getEndPos();
        if (fileSize > MAX_PREFERENCES_FILE_SIZE) {
            Debug.log(.ERROR, "PreferencesManager: Preferences file size ({d} bytes) exceeds maximum ({d} bytes)", .{ fileSize, MAX_PREFERENCES_FILE_SIZE });
            return PreferenceError.FileSizeExceeded;
        }

        // Read file contents
        const contents = file.readToEndAlloc(self.allocator, MAX_PREFERENCES_FILE_SIZE) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: Failed to read preferences file: {any}", .{err});
            return PreferenceError.IoFailure;
        };
        defer self.allocator.free(contents);

        // Handle empty file: use defaults and persist
        if (contents.len == 0) {
            Debug.log(.WARNING, "PreferencesManager: Preferences file is empty; using defaults", .{});
            try self.persist();
            return;
        }

        // Parse JSON with validation
        const parsed = json.parseFromSlice(FilePayload, self.allocator, contents, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: Failed to parse preferences JSON; reverting to defaults. Error: {any}", .{err});
            try self.persist();
            return PreferenceError.InvalidPreferences;
        };
        defer parsed.deinit();

        // Load checkUpdates preference
        if (parsed.value.checkUpdates) |value| {
            self.data.checkUpdates = value;
        }

        // Load debugLevel with bounds validation
        if (parsed.value.debugLevel) |value| {
            const minLevel = @intFromEnum(SeverityLevel.DEBUG);
            const maxLevel = @intFromEnum(SeverityLevel.ERROR);
            if (value >= minLevel and value <= maxLevel) {
                self.data.debugLevel = @enumFromInt(value);
            } else {
                Debug.log(.WARNING, "PreferencesManager: Invalid debugLevel {d}; using default", .{value});
                return PreferenceError.InvalidPreferences;
            }
        }

        // Load forceHelperInstall preference
        if (parsed.value.forceHelperInstall) |value| {
            self.data.forceHelperInstall = value;
        }
    }

    /// Ensures the directory containing the preferences file exists, creating if necessary.
    /// `Returns`: PreferenceError.IoFailure if directory creation fails
    fn ensureDirectoryExists(self: *PreferencesManager) !void {
        const dirPath = std.fs.path.dirname(self.getPath()) orelse return;

        std.fs.makeDirAbsolute(dirPath) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                Debug.log(.ERROR, "PreferencesManager: Failed to create directory {s}: {any}", .{ dirPath, err });
                return PreferenceError.IoFailure;
            },
        };
    }

    /// Persists current preferences to disk as JSON.
    /// Handles file creation on first write with recursion depth limit to prevent stack overflow.
    ///
    /// The recursion occurs when:
    /// 1. File doesn't exist initially
    /// 2. Creation succeeds but opening for write fails (rare but possible)
    /// 3. Recursion depth prevents infinite loops on permission errors
    ///
    /// `Returns`: PreferenceError.IoFailure if any file operation fails
    ///          PreferenceError.MaxPersistDepthExceeded if recursion depth exceeded
    fn persist(self: *PreferencesManager) !void {
        // Prevent stack overflow from recursive persist attempts
        if (self.persistDepth >= MAX_PERSIST_RECURSION_DEPTH) {
            Debug.log(.ERROR, "PreferencesManager: Maximum persist recursion depth exceeded; possible permission issue", .{});
            return PreferenceError.MaxPersistDepthExceeded;
        }

        try self.ensureDirectoryExists();

        const pathStr = self.getPath();
        Debug.log(.DEBUG, "PreferencesManager.persist: Writing preferences to {s} (depth: {d})", .{ pathStr, self.persistDepth });

        // Split path into directory and filename
        const dirPath = std.fs.path.dirname(pathStr) orelse {
            Debug.log(.ERROR, "PreferencesManager.persist: Unable to extract directory from path: {s}", .{pathStr});
            return PreferenceError.IoFailure;
        };
        const fileName = std.fs.path.basename(pathStr);

        // Open directory
        var dir = std.fs.openDirAbsolute(dirPath, .{}) catch |err| {
            Debug.log(.ERROR, "PreferencesManager: Failed to open directory {s}: {any}", .{ dirPath, err });
            return PreferenceError.IoFailure;
        };
        defer dir.close();

        // Open or create file
        var file = dir.openFile(fileName, .{ .mode = .write_only }) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                // File doesn't exist yet; create it and retry with recursion
                _ = dir.createFile(fileName, .{}) catch |createErr| {
                    Debug.log(.ERROR, "PreferencesManager: Failed to create preferences file: {any}", .{createErr});
                    return PreferenceError.IoFailure;
                };

                // Retry opening for write (now file exists)
                self.persistDepth += 1;
                defer self.persistDepth -= 1;
                return try self.persist();
            },
            else => {
                Debug.log(.ERROR, "PreferencesManager: Failed to open preferences file for writing: {any}", .{err});
                return PreferenceError.IoFailure;
            },
        };
        defer file.close();

        // Truncate file to ensure clean write
        try file.setEndPos(0);

        // Format preferences as JSON payload
        const jsonPayload = try std.fmt.allocPrint(self.allocator, "{{\"checkUpdates\":{},\"debugLevel\":{},\"forceHelperInstall\":{}}}", .{
            self.data.checkUpdates,
            @intFromEnum(self.data.debugLevel),
            self.data.forceHelperInstall,
        });
        defer self.allocator.free(jsonPayload);

        try file.writeAll(jsonPayload);

        // Ensure data is flushed to disk for durability guarantee
        try file.sync();

        Debug.log(.DEBUG, "PreferencesManager: Preferences successfully written and flushed", .{});
    }
};

var instance: ?PreferencesManager = null;
var mutex: std.Thread.Mutex = .{};

/// Initializes the preferences manager singleton.
/// Must be called exactly once at application startup before accessing preferences.
///
/// Arguments:
///   allocator: Memory allocator for temporary allocations
///   absolutePath: Absolute path to preferences file (must be null-terminated)
///
/// Returns: true if this is first application launch (new preferences file created)
///          false if preferences file already existed
///          PreferenceError.AlreadyInitialized if init() called more than once
///          PreferenceError.PathTooLong if path exceeds maximum
///          PreferenceError.InvalidPath if path contains invalid sequences
///          PreferenceError.IoFailure if file I/O fails
pub fn init(allocator: std.mem.Allocator, absolutePath: [:0]const u8) !bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance != null) {
        Debug.log(.ERROR, "PreferencesManager.init() called but instance already initialized", .{});
        return PreferenceError.AlreadyInitialized;
    }

    const manager = try PreferencesManager.init(allocator, absolutePath);
    instance = manager;

    if (manager.isFirstLaunch) {
        Debug.log(.INFO, "PreferencesManager: First launch detected", .{});
    } else {
        Debug.log(.INFO, "PreferencesManager: Preferences loaded from {s}", .{manager.getPath()});
    }

    return manager.isFirstLaunch;
}

/// Deinitializes the preferences manager singleton.
/// Called at application shutdown.
pub fn deinit() void {
    mutex.lock();
    defer mutex.unlock();
    instance = null;
    Debug.log(.INFO, "PreferencesManager: Singleton deinitialized", .{});
}

/// Requests user permission for update checking via UI dialog.
/// Shows a native OS dialog and persists the user's choice.
///
/// IMPORTANT: This function releases the mutex before showing the dialog
/// to prevent blocking other preference operations during UI interaction.
///
/// Returns: User's choice (true = allow updates, false = deny)
///          false if preferences manager not initialized
pub fn getCheckUpdatesPermission() bool {
    // Check instance existence while holding lock
    const isInitialized = blk: {
        mutex.lock();
        defer mutex.unlock();

        break :blk instance != null;
    };

    if (!isInitialized) {
        Debug.log(.WARNING, "PreferencesManager.getCheckUpdatesPermission() called but manager not initialized", .{});
        return false;
    }

    // Show dialog OUTSIDE the mutex lock to prevent blocking other threads
    const allowUpdateChecking = osd.message(
        "Allow Freetracer to check for updates on github.com?\n\nNote: update check is performed once upon app startup. Updates are strongly recommended for application and system security.",
        .{ .buttons = .yes_no, .level = .info },
    );

    // Re-acquire lock to update state
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        inst.data.checkUpdates = allowUpdateChecking;
        inst.persist() catch |err| {
            Debug.log(.ERROR, "PreferencesManager: Failed to save user preference: {any}", .{err});
            _ = osd.message("Failed to save user preference. Please consider reporting as a bug.", .{ .buttons = .ok, .level = .err });
        };
        inst.isFirstLaunch = false;
    }

    return allowUpdateChecking;
}

/// Retrieves the current check-updates preference.
///
/// Returns: Current preference value
///          PreferenceError.NotInitialized if manager not initialized
pub fn getCheckUpdates() !bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| {
        return inst.data.checkUpdates;
    }
    return PreferenceError.NotInitialized;
}

/// Sets the check-updates preference and persists to disk if changed.
///
/// Arguments:
///   value: New preference value
///
/// Returns: PreferenceError.NotInitialized if manager not initialized
///          PreferenceError.IoFailure if persistence fails
pub fn setCheckUpdates(value: bool) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.data.checkUpdates != value) {
            inst.data.checkUpdates = value;
            try inst.persist();
        }
        return;
    }
    return PreferenceError.NotInitialized;
}

/// Retrieves the current debug level preference.
///
/// Returns: Current debug severity level
///          PreferenceError.NotInitialized if manager not initialized
pub fn getDebugLevel() !SeverityLevel {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| {
        return inst.data.debugLevel;
    }
    return PreferenceError.NotInitialized;
}

/// Sets the debug level preference and persists to disk if changed.
///
/// Arguments:
///   value: New debug severity level
///
/// Returns: PreferenceError.NotInitialized if manager not initialized
///          PreferenceError.IoFailure if persistence fails
pub fn setDebugLevel(value: SeverityLevel) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.data.debugLevel != value) {
            inst.data.debugLevel = value;
            try inst.persist();
        }
        return;
    }
    return PreferenceError.NotInitialized;
}

/// Retrieves the force-helper-install preference.
///
/// Returns: Current preference value
///          PreferenceError.NotInitialized if manager not initialized
pub fn getForceHelperInstall() !bool {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| {
        return inst.data.forceHelperInstall;
    }
    return PreferenceError.NotInitialized;
}

/// Sets the force-helper-install preference and persists to disk if changed.
///
/// Arguments:
///   value: New preference value
///
/// Returns: PreferenceError.NotInitialized if manager not initialized
///          PreferenceError.IoFailure if persistence fails
pub fn setForceHelperInstall(value: bool) !void {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |*inst| {
        if (inst.data.forceHelperInstall != value) {
            inst.data.forceHelperInstall = value;
            try inst.persist();
        }
        return;
    }
    return PreferenceError.NotInitialized;
}

/// Retrieves the absolute path to the preferences file.
///
/// Returns: Path to preferences file (null-terminated)
///          PreferenceError.NotInitialized if manager not initialized
pub fn getPath() ![:0]const u8 {
    mutex.lock();
    defer mutex.unlock();

    if (instance) |inst| return inst.getPath();
    return PreferenceError.NotInitialized;
}
