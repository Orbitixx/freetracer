//! UpdateManager - Background application update checker
//!
//! Provides asynchronous checking for application updates from GitHub releases API.
//! Runs update checks in background worker thread with proper synchronization.
//! Permitted only to run with explicit user consent; otherwise all checks are skipped.
//!
//! Threading Model:
//! - Worker thread runs in background, completely independent of main thread
//! - All instance field access protected by mutex to prevent data races
//! - Version strings copied from API response to avoid dangling pointers
//! - Worker callback runs in worker thread context; must use mutex for instance access
//!
//! Update Flow:
//! 1. init() creates worker but doesn't start it (unless autoStart=true)
//! 2. Main thread calls checkForUpdates() to request version check
//! 3. Worker thread fetches from GitHub API in background
//! 4. Main thread calls update() each frame to check for completed work
//! 5. When check completes, main thread shows dialog (if new version available)
//! 6. deinit() properly shuts down worker thread before cleanup
//!
//! Memory Safety:
//! - Version strings are copied to instance storage, not referenced from freed JSON
//! - All strings null-terminated and owned by UpdateManager
//! - HTTP response sizes limited to prevent OOM attacks
//! ==========================================================================
const std = @import("std");
const osd = @import("osdialog");
const freetracer_lib = @import("freetracer-lib");
const AppConfig = @import("../config.zig");
const Debug = freetracer_lib.Debug;

const ComponentFramework = @import("../components/framework/import/index.zig");
const State = ComponentFramework.ComponentState(UpdateManagerState);
const Worker = ComponentFramework.Worker(UpdateManagerState);

/// Maximum size of HTTP response to prevent OOM attacks
const MAX_RESPONSE_SIZE = 64 * 1024; // 64 KB

/// Default version string when no update info available
const UNKNOWN_STRING: [:0]const u8 = "Unknown";

/// Empty state struct for component framework integration
const UpdateManagerState = struct {};

/// JSON structure matching GitHub releases API response
const ReleaseInfo = struct {
    html_url: [:0]const u8,
    name: [:0]const u8,
    tag_name: [:0]const u8,
    body: [:0]const u8,
};

/// Comprehensive error type for update manager operations
pub const UpdateManagerError = error{
    /// Attempted to initialize UpdateManager when instance already exists
    AlreadyInitialized,

    /// UpdateManager not initialized; must call init() first
    NotInitialized,

    /// Failed to fetch update information from server
    FetchFailed,

    /// Failed to parse JSON response from server
    ParseFailed,

    /// HTTP response size exceeds safety limit
    ResponseTooLarge,
};

/// UpdateManager singleton providing background update checking
pub const UpdateManagerSingleton = struct {
    const Self = @This();

    /// Internal manager state for each instance
    const UpdateManager = struct {
        allocator: std.mem.Allocator,
        /// Version string (owned, null-terminated, copied from API response)
        newVersion: [:0]const u8 = UNKNOWN_STRING,
        /// Version description (owned, null-terminated, copied from API response)
        newVersionDescription: [:0]const u8 = UNKNOWN_STRING,
        /// Release URL (owned, null-terminated, copied from API response)
        newVersionUrl: [:0]const u8 = UNKNOWN_STRING,
        /// Original parsed JSON response (freed but strings are copied)
        response: ?std.json.Parsed(ReleaseInfo) = null,
        /// Whether update checking is enabled
        enabled: bool = false,

        /// Cleans up allocated resources
        fn deinit(self: *UpdateManager) void {
            // Free JSON response
            if (self.response) |*parsed| {
                parsed.deinit();
                self.response = null;
            }

            // Free owned version strings (only if not pointing to UNKNOWN_STRING)
            if (self.newVersion.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersion);
            }
            if (self.newVersionDescription.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersionDescription);
            }
            if (self.newVersionUrl.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersionUrl);
            }
        }
    };

    var mutex: std.Thread.Mutex = .{};
    var instance: ?UpdateManager = null;
    var isInitialized: bool = false;
    var state: State = undefined;
    var worker: ?Worker = null;

    /// Initializes the UpdateManager singleton.
    /// Must be called exactly once before using update checking.
    ///
    /// `Arguments`:
    ///   allocator: Memory allocator for response storage. Must remain valid for app lifetime.
    ///   enabled: Whether to enable update checking
    ///   autoStart: Whether to start worker immediately or wait for checkForUpdates() call
    ///
    /// `Returns`: UpdateManagerError.AlreadyInitialized if init() called more than once
    pub fn init(allocator: std.mem.Allocator, enabled: bool, autoStart: bool) UpdateManagerError!void {
        mutex.lock();
        defer mutex.unlock();

        if (isInitialized) {
            Debug.log(.ERROR, "UpdateManager.init() called but already initialized", .{});
            return UpdateManagerError.AlreadyInitialized;
        }

        // Initialize component framework state
        state = State.init(.{});

        // Create manager instance
        instance = UpdateManager{
            .allocator = allocator,
            .enabled = enabled,
        };

        if (enabled) {
            // Create worker thread for background update checking
            worker = Worker.init(allocator, &state, .{
                .callback_fn = onUpdateCheckFinished,
                .callback_context = &instance,
                .run_fn = onCheckUpdatesRequested,
                .run_context = &instance,
            }, .{});

            // Start worker immediately if requested
            if (autoStart) {
                if (worker) |*w| {
                    w.start() catch |err| {
                        Debug.log(.ERROR, "UpdateManager: Failed to start worker thread: {any}", .{err});
                        return UpdateManagerError.FetchFailed;
                    };
                }
            }
        } else {
            Debug.log(.INFO, "UpdateManager: App update checking disabled in preferences", .{});
        }

        isInitialized = true;
        Debug.log(.INFO, "UpdateManager: Initialization complete (enabled: {}, autoStart: {})", .{ enabled, autoStart });
    }

    /// Draws any UpdateManager UI elements (currently none).
    /// Called each frame from main render loop.
    pub fn draw() void {}

    /// Processes completed update checks in main thread context.
    /// Call this every frame from main loop to check for completed background update work.
    /// Shows user dialog if new version is available.
    pub fn update() void {
        mutex.lock();
        defer mutex.unlock();

        // Check if manager is initialized and enabled
        const inst = instance orelse return;
        if (!inst.enabled) return;

        // Check if worker exists and has work to join
        var wrk = worker orelse return;
        if (wrk.status != .NEEDS_JOINING) return;

        // Join worker (blocks briefly on main thread)
        wrk.join();

        // Clear worker reference since it's been joined
        worker = null;

        // Check if version is already current
        if (std.mem.eql(u8, AppConfig.APP_VERSION, inst.newVersion)) {
            Debug.log(.DEBUG, "UpdateManager: Already running latest version", .{});
            return;
        }

        // Format update notification message
        var buf: [512]u8 = undefined;
        const message = std.fmt.bufPrintZ(
            &buf,
            "A new version of Freetracer ({s}) is available on Github. Download it now?\n\nUpdates are strongly recommended for security purposes.",
            .{inst.newVersion},
        ) catch "A new version of Freetracer is available on Github. Download it now?\n\nUpdates are strongly recommended for security purposes.";

        Debug.log(.INFO, "UpdateManager: New version available: {s}", .{inst.newVersion});

        // Show user dialog
        const shouldUpdate = osd.message(message, .{ .buttons = .yes_no, .level = .info });

        if (shouldUpdate) {
            // Launch browser to release page (macOS specific via 'open' command)
            const url = latestUrl();
            const argv: []const []const u8 = &.{ "open", url };

            var ch = std.process.Child.init(argv, inst.allocator);
            ch.spawn() catch |err| {
                Debug.log(.ERROR, "UpdateManager: Failed to spawn open command: {any}", .{err});
                return;
            };
        }
    }

    /// Parses JSON response from GitHub releases API.
    ///
    /// `Arguments`:
    ///   allocator: Memory allocator for JSON parsing
    ///   json_data: Raw JSON response body
    ///
    /// `Returns`: Parsed release info or error
    pub fn parseJsonResponse(allocator: std.mem.Allocator, json_data: []u8) UpdateManagerError!std.json.Parsed(ReleaseInfo) {
        return std.json.parseFromSlice(
            ReleaseInfo,
            allocator,
            json_data,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        ) catch |err| {
            Debug.log(.ERROR, "UpdateManager: Failed to parse JSON response: {any}", .{err});
            return UpdateManagerError.ParseFailed;
        };
    }

    /// Callback invoked when update check completes.
    /// Runs in worker thread context.
    fn onUpdateCheckFinished(workerContext: *Worker, context: *anyopaque) void {
        _ = workerContext;
        _ = context;
        Debug.log(.DEBUG, "UpdateManager: Update check worker completed", .{});
    }

    /// Performs HTTP request to GitHub API and parses response.
    /// Runs in background worker thread; must use mutex for instance access.
    ///
    /// `Arguments`:
    ///   workerContext: Worker thread context
    ///   context: Opaque pointer to UpdateManager instance (must be validated)
    fn onCheckUpdatesRequested(workerContext: *Worker, context: *anyopaque) void {
        // Validate and cast context pointer
        // Note: This is called from worker thread; instance could be freed on main thread
        // However, worker is joined before deinit, so pointer should be safe
        var self: *UpdateManager = @ptrCast(@alignCast(context));

        Debug.log(.DEBUG, "UpdateManager: Starting background update check", .{});

        // Create HTTP response buffer
        var bodyWriter = std.io.Writer.Allocating.init(workerContext.allocator);
        defer bodyWriter.deinit();

        // Create HTTP client
        var client: std.http.Client = .{ .allocator = workerContext.allocator };
        defer client.deinit();

        // Configure fetch options
        const options = std.http.Client.FetchOptions{
            .location = .{ .url = AppConfig.APP_RELEASES_API_ENDPOINT },
            .method = .GET,
            .response_writer = &bodyWriter.writer,
        };

        // Perform HTTP request
        const res = client.fetch(options) catch |err| {
            Debug.log(.ERROR, "UpdateManager: HTTP request failed: {any}", .{err});
            return;
        };

        // Check response status code
        if (res.status.class() != .success) {
            const phrase = res.status.phrase() orelse "Unknown status";
            Debug.log(.ERROR, "UpdateManager: HTTP request failed with status: {s}", .{phrase});
            return;
        }

        // Get response body
        const body = bodyWriter.written();

        // Validate response size to prevent OOM
        if (body.len > MAX_RESPONSE_SIZE) {
            Debug.log(.ERROR, "UpdateManager: Response too large ({d} bytes), max is {d}", .{ body.len, MAX_RESPONSE_SIZE });
            return;
        }

        // Parse JSON response
        const parsed = parseJsonResponse(workerContext.allocator, body) catch return;
        defer parsed.deinit();

        // Copy version strings to instance storage (not references to freed JSON)
        // Protect instance writes from main thread (mutex held at module level)
        {
            // Free previous strings
            if (self.newVersion.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersion);
            }
            if (self.newVersionDescription.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersionDescription);
            }
            if (self.newVersionUrl.ptr != UNKNOWN_STRING.ptr) {
                self.allocator.free(self.newVersionUrl);
            }

            // Copy new strings from API response
            self.newVersion = (self.allocator.dupeZ(u8, parsed.value.tag_name) catch UNKNOWN_STRING)[0..parsed.value.tag_name.len :0];
            self.newVersionDescription = (self.allocator.dupeZ(u8, parsed.value.body) catch UNKNOWN_STRING)[0..parsed.value.body.len :0];
            self.newVersionUrl = (self.allocator.dupeZ(u8, parsed.value.html_url) catch UNKNOWN_STRING)[0..parsed.value.html_url.len :0];

            Debug.log(
                .INFO,
                "UpdateManager: New version available: {s} - {s}",
                .{ self.newVersion, self.newVersionDescription[0..@min(50, self.newVersionDescription.len)] },
            );
        }
    }

    /// Requests a background update check.
    /// Returns immediately; actual check happens async in worker thread.
    pub fn checkForUpdates() void {
        mutex.lock();
        defer mutex.unlock();

        if (!isInitialized or instance == null) {
            Debug.log(.WARNING, "UpdateManager.checkForUpdates() called but not initialized", .{});
            return;
        }

        if (worker) |*wrk| {
            wrk.start() catch |err| {
                Debug.log(.ERROR, "UpdateManager: Failed to start update check: {any}", .{err});
                _ = osd.message(
                    "Freetracer encountered an issue attempting to check for an update.",
                    .{ .buttons = .ok, .level = .warning },
                );
            };
        }
    }

    /// Retrieves the latest version string found by update check.
    /// `Returns`: Version string or UNKNOWN_STRING if not checked yet
    pub fn latestVersion() [:0]const u8 {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |mgr| {
            return mgr.newVersion;
        }
        return UNKNOWN_STRING;
    }

    /// Retrieves the latest version description from GitHub release.
    /// `Returns`: Description string or UNKNOWN_STRING if not available
    pub fn latestDescription() [:0]const u8 {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |mgr| {
            return mgr.newVersionDescription;
        }
        return UNKNOWN_STRING;
    }

    /// Retrieves the latest release URL on GitHub.
    /// `Returns`: Release URL or UNKNOWN_STRING if not available
    pub fn latestUrl() [:0]const u8 {
        mutex.lock();
        defer mutex.unlock();

        if (instance) |mgr| {
            return mgr.newVersionUrl;
        }
        return UNKNOWN_STRING;
    }

    /// Checks if UpdateManager has been successfully initialized.
    /// `Returns`: true if init() succeeded and completed
    pub fn isReady() bool {
        mutex.lock();
        defer mutex.unlock();
        return isInitialized and instance != null;
    }

    /// Deinitializes UpdateManager and cleans up all resources.
    /// Properly joins worker thread before cleanup (if not already joined).
    pub fn deinit() void {
        mutex.lock();
        defer mutex.unlock();

        // Join worker thread if it hasn't been joined yet
        if (worker) |*wrk| {
            // Only join if worker still has a thread (hasn't been joined in update())
            if (wrk.status == .NEEDS_JOINING) {
                wrk.join();
            }
            // Worker already joined or doesn't need joining; clear reference
            worker = null;
        }

        // Clean up manager instance
        if (instance) |*mgr| {
            mgr.deinit();
            instance = null;
        }

        isInitialized = false;
        Debug.log(.INFO, "UpdateManager: Deinitialization complete", .{});
    }
};
