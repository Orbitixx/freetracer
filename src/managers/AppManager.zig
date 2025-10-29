//! AppManager - Primary application state machine and lifecycle coordinator
//!
//! This manager orchestrates the entire application lifecycle, including:
//! - Application state transitions (image selection → device selection → flashing)
//! - Component initialization and lifecycle management
//! - UI layout management and event propagation
//! - Error handling with user-facing feedback
//!
//! The manager implements a strict state machine pattern to ensure valid transitions
//! and provides comprehensive error reporting to users via OSD dialogs.
//! =================================================================================
const std = @import("std");
const rl = @import("raylib");
const osd = @import("osdialog");

const AppConfig = @import("../config.zig");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const fs = freetracer_lib.fs;

const ResourceManager = @import("./ResourceManager.zig").ResourceManagerSingleton;
const PreferencesManager = @import("./PreferencesManager.zig");
const WindowManager = @import("./WindowManager.zig").WindowManagerSingleton;
const EventManager = @import("./EventManager.zig").EventManagerSingleton;
const UpdateManager = @import("./UpdateManager.zig").UpdateManagerSingleton;

const Font = ResourceManager.FONT;
const Color = @import("../components/ui/Styles.zig").Color;

const ComponentFramework = @import("../components/framework/import/index.zig");
const ComponentID = ComponentFramework.ComponentID;

const FilePicker = @import("../components/FilePicker/FilePicker.zig");
const DeviceList = @import("../components/DeviceList/DeviceList.zig");
const DataFlasher = @import("../components/DataFlasher/DataFlasher.zig");
const PrivilegedHelper = @import("../components/macos/PrivilegedHelper.zig");

const UI = @import("../components/ui/import/index.zig");
const Button = @import("../components/ui/Button.zig");
const Checkbox = @import("../components/ui/Checkbox.zig");
const Rectangle = UI.RectanglePro;

const UIFramework = @import("../components/ui/framework/import.zig");
const Transform = UIFramework.Transform;
const View = UIFramework.View;
const UIChain = UIFramework.UIChain;
const Texture = UIFramework.Texture;

const relY = WindowManager.relH;
const relX = WindowManager.relW;

pub const AppManagerSingleton = @This();

/// Represents the application workflow state machine
/// States transition in a linear sequence: ImageSelection → DeviceSelection →
/// SelectionConfirmation → DataFlashing → Idle.
/// AppReset event resets the state back to ImageSelection.
/// Invalid transitions return an error and notify the user via OSD.
const AppState = enum(u8) {
    /// User selects an ISO image file
    ImageSelection,
    /// User selects a target device
    DeviceSelection,
    /// User confirms the image and device selection
    SelectionConfirmation,
    /// Active data flashing in progress
    DataFlashing,
    /// Idle state after successful flashing or error recovery
    Idle,
};

/// Requests for component activation (and validation of intent) based on application state
/// Each request is validated against current state and last action before authorization
const ActionRequest = enum(u8) {
    /// Request to activate the device list component
    ActivateDeviceList,
    /// Request to activate the data flasher component
    ActivateDataFlasher,
    /// Request to begin the data flashing process
    BeginDataFlashing,
};

/// Reports state-changing actions from components
/// Each report validates the application state and triggers state machine advancement
const ActionReport = enum(u8) {
    /// ISO image file has been selected by user
    ImageSelected,
    /// Storage device has been selected by user
    DeviceSelected,
    /// User confirmed the image and device selection
    SelectionConfirmed,
    /// Data flashing completed successfully
    DataFlashed,
    /// Data flashing failed; state reverted to SelectionConfirmation
    FlashFailed,
};

/// Defines application-level events whhich this element emits.
pub const Events = struct {
    /// Emitted when user resets the application to initial state
    pub const AppResetEvent = ComponentFramework.defineEvent(
        EventManager.createEventName("AppManager", "on_app_reset_requested"),
        struct {},
        struct {},
    );
};

// Singleton instance of the AppManager - initialized once during application startup
var instance: ?AppManager = null;

/// Initializes the AppManager singleton instance.
/// Must be called exactly once before startApp(). Calling multiple times results in an error.
/// The allocator provided should remain valid for the entire application lifetime.
/// `Arguments`:
///   allocator: Memory allocator for internal allocations
/// `Errors`:
///   error.AppManagerInstanceAlreadyExists: Called when instance already initialized
pub fn init(allocator: std.mem.Allocator) !void {
    if (instance != null) {
        Debug.log(.ERROR, "Attempted to init() an App Manager instance despite one already initialized.", .{});
        _ = osd.message("AppManager already initialized. This is a critical bug.", .{ .buttons = .ok, .level = .err });
        return error.AppManagerInstanceAlreadyExists;
    }

    instance = .{
        .allocator = allocator,
        .appState = .ImageSelection,
        .lastAction = null,
        .globalTransform = .{},
        .layout = undefined,
    };

    Debug.log(.INFO, "AppManager initialized successfully", .{});
}

/// Starts the application main loop.
/// Must be called after init(). Blocks until application window is closed.
/// Manages the entire application lifecycle including component initialization,
/// event loop processing, and clean resource deallocation.
/// `Errors`:
///   error.AppManagerInstanceIsNULL: Called before init()
pub fn startApp() !void {
    if (instance) |*inst| {
        return inst.run();
    }
    Debug.log(.ERROR, "Attempted to start app without initializing AppManager", .{});
    _ = osd.message("Application manager not initialized. Cannot start application.", .{ .buttons = .ok, .level = .err });
    return error.AppManagerInstanceIsNULL;
}

/// Validates whether a requested action is valid for the current application state
/// Implements state machine authorization - only certain actions are permitted in each state.
/// Used by components to verify they can proceed with their operation.
/// `Arguments`:
///   action: The action request to validate
/// `Returns`:
///   true if the action is valid for the current state, false otherwise
pub fn authorizeAction(action: ActionRequest) bool {
    if (instance) |*inst| {
        const is_valid = inst.isValidAction(action);
        Debug.log(.INFO, "AppManager authorized action: {any}, state: {any}, valid: {}", .{ action, inst.appState, is_valid });
        return is_valid;
    }
    Debug.log(.ERROR, "Attempted to authorize action without initialized AppManager", .{});
    return false;
}

/// Reports a state-changing action and triggers state machine advancement
/// Called by components to report completion of actions. Validates the action and
/// advances the state machine accordingly. Provides user feedback via OSD on errors.
/// `Arguments`:
///   action: The action being reported
/// `Errors`:
///   error.AppManagerInstanceIsNULL: Called before init()
///   Various transition errors from advanceState()
pub fn reportAction(action: ActionReport) !void {
    if (instance) |*inst| {
        return inst.handleActionReport(action);
    }

    Debug.log(.ERROR, "Attempted to report action without initialized AppManager", .{});
    _ = osd.message("Application manager not initialized. Cannot process action report.", .{ .buttons = .ok, .level = .err });
    return error.AppManagerInstanceIsNULL;
}

/// Retrieves the current application state.
/// `Returns`:
///   Current AppState
/// `Errors`:
///   error.AppManagerInstanceIsNULL: Called before init()
pub fn getState() !AppState {
    if (instance) |inst| {
        return inst.appState;
    }
    Debug.log(.ERROR, "Attempted to get state without initialized AppManager", .{});
    return error.AppManagerInstanceIsNULL;
}

/// Retrieves the global transform used for UI layout.
/// The returned pointer is valid for the entire application lifetime.
/// `Returns`:
///   Pointer to the global Transform
/// `Errors`:
///   error.AppManagerInstanceIsNULL: Called before init()
pub fn getGlobalTransform() !*Transform {
    if (instance) |*inst| {
        return &inst.globalTransform;
    }
    Debug.log(.ERROR, "Attempted to get global transform without initialized AppManager", .{});
    return error.AppManagerInstanceIsNULL;
}

/// Private AppManager implementation struct
/// Contains the core state machine and lifecycle logic.
/// Access through public singleton functions only.
const AppManager = struct {
    allocator: std.mem.Allocator,
    appState: AppState,
    lastAction: ?ActionReport,
    globalTransform: Transform,
    layout: View,

    /// Advances the application state to the next state in the workflow.
    /// Implements linear state machine transitions and synchronizes UI elements
    /// to reflect the new state. Each state transition may emit UI events to
    /// update components accordingly.
    ///
    /// `State Transitions`:
    ///   ImageSelection        → DeviceSelection
    ///   DeviceSelection       → SelectionConfirmation
    ///   SelectionConfirmation → DataFlashing
    ///   DataFlashing          → Idle
    ///   Idle                  → ERROR (terminal state, cannot advance)
    ///
    /// `Side Effects`:
    ///   - Resets mouse cursor to default
    ///   - Emits UI events to own layout to synchronize component states
    ///   - Logs state transitions for debugging
    ///
    /// `Errors`:
    ///   error.CannotAdvanceStatePastDataFlashedState: Attempted to advance from Idle state
    fn advanceState(self: *AppManager) !void {
        // Validate we're not trying to advance from terminal state
        if (self.appState == .Idle) {
            Debug.log(.ERROR, "Cannot advance state from Idle. State machine is in terminal state.", .{});
            _ = osd.message("Already in final state. Please reset to continue.", .{ .buttons = .ok, .level = .warning });
            return error.CannotAdvanceStatePastDataFlashedState;
        }

        // Advance to next state in the workflow
        self.appState = switch (self.appState) {
            .ImageSelection => .DeviceSelection,
            .DeviceSelection => .SelectionConfirmation,
            .SelectionConfirmation => .DataFlashing,
            .DataFlashing => .Idle,
            .Idle => unreachable, // Validated above
        };

        rl.setMouseCursor(.default);

        // Emit state-specific UI events
        try self.emitStateChangeEvents();

        Debug.log(.INFO, "AppManager: state advanced to {any}", .{self.appState});
    }

    /// Emits UI events appropriate for the current state.
    /// Each state transition requires specific UI updates that are managed here.
    ///
    /// `Side Effects`:
    ///   - Modifies satellite graphic position
    ///   - Updates reset button visibility and enabled state
    fn emitStateChangeEvents(self: *AppManager) !void {
        // Move satellite graphic when entering confirmation state
        if (self.appState == .SelectionConfirmation) {
            self.layout.emitEvent(
                .{ .PositionChanged = .{ .target = .AppManagerSatteliteGraphic, .position = .percent(0.3, 0.3) } },
                .{ .excludeSelf = true },
            );
        }

        // Enable reset button when exiting initial state
        if (self.appState != .ImageSelection) {
            self.layout.emitEvent(
                .{ .StateChanged = .{ .target = .AppManagerResetAppButton, .isActive = true } },
                .{ .excludeSelf = true },
            );
        }

        // Disable reset button during flashing to prevent interruption
        if (self.appState == .DataFlashing) {
            self.layout.emitEvent(
                .{ .SpriteButtonEnabledChanged = .{ .target = .AppManagerResetAppButton, .enabled = false } },
                .{ .excludeSelf = true },
            );
        }

        // Re-enable reset button after flashing completes
        if (self.appState == .Idle) {
            self.layout.emitEvent(
                .{ .SpriteButtonEnabledChanged = .{ .target = .AppManagerResetAppButton, .enabled = true } },
                .{ .excludeSelf = true },
            );
        }
    }

    /// Resets the application to its initial state.
    /// Triggered by user clicking the "Start Over" button. Validates that flashing
    /// is not in progress (cannot interrupt an active operation) and then:
    ///   1. Resets application state to ImageSelection
    ///   2. Clears last action history
    ///   3. Broadcasts AppResetEvent to all listeners
    ///   4. Updates UI to reflect initial state
    ///
    /// `Side Effects`:
    ///   - Modifies all component states (via AppResetEvent)
    ///   - Updates UI element positions and visibility
    ///   - Clears workflow history
    fn resetState(self: *AppManager) void {
        if (self.appState == .DataFlashing) {
            Debug.log(.WARNING, "AppManager: Cannot reset state during active data flashing operation.", .{});
            _ = osd.message("Cannot reset while data is being flashed. Please wait for the operation to complete.", .{ .buttons = .ok, .level = .warning });
            return;
        }

        self.appState = .ImageSelection;
        self.lastAction = null;

        // Broadcast reset event to all components
        const resetEvent = Events.AppResetEvent.create(null, null);
        EventManager.broadcast(resetEvent);

        // Synchronize UI state with application reset
        self.layout.emitEvent(
            .{ .StateChanged = .{ .target = .AppManagerResetAppButton, .isActive = false } },
            .{ .excludeSelf = true },
        );

        self.layout.emitEvent(
            .{ .PositionChanged = .{ .target = .AppManagerSatteliteGraphic, .position = .percent(0.7, 0.3) } },
            .{ .excludeSelf = true },
        );

        Debug.log(.INFO, "AppManager: state successfully reset to {any}", .{self.appState});
    }

    /// Validates whether an action request is permissible in the current state.
    /// Implements the state machine authorization policy. Each action has specific
    /// prerequisites that must be met before it can be executed.
    ///
    /// `Arguments`:
    ///   action: The action to validate
    ///
    /// `Returns`:
    ///   true if action is valid for current state, false otherwise
    fn isValidAction(self: *AppManager, action: ActionRequest) bool {
        // No action is valid if we have no action history
        if (self.lastAction == null) {
            Debug.log(.DEBUG, "AppManager: Action {any} invalid - no prior action recorded", .{action});
            return false;
        }

        const isValid = switch (action) {
            .ActivateDeviceList => (self.lastAction.? == .ImageSelected and self.appState == .DeviceSelection),
            .ActivateDataFlasher => (self.lastAction.? == .DeviceSelected and self.appState == .SelectionConfirmation),
            .BeginDataFlashing => (self.lastAction.? == .SelectionConfirmed and self.appState == .DataFlashing),
        };

        if (!isValid) {
            Debug.log(.WARNING, "AppManager: Action {any} invalid - lastAction: {any}, state: {any}", .{ action, self.lastAction, self.appState });
        }

        return isValid;
    }

    /// Handles an action report from a component.
    /// Implements the core state machine logic by processing action reports and
    /// advancing the state machine accordingly. Provides appropriate user feedback
    /// for both success and error cases.
    ///
    /// `Arguments`:
    ///   action: The action being reported
    ///
    /// `Errors`:
    ///   Propagated from advanceState() on invalid state transitions
    fn handleActionReport(self: *AppManager, action: ActionReport) !void {
        switch (action) {
            .ImageSelected, .DeviceSelected, .SelectionConfirmed, .DataFlashed => {
                Debug.log(.DEBUG, "AppManager: processing action report: {any}, current state: {any}", .{ action, self.appState });

                self.lastAction = action;
                try self.advanceState();

                Debug.log(.DEBUG, "AppManager: state successfully transitioned to {any} following {any}", .{ self.appState, action });
            },
            .FlashFailed => {
                Debug.log(.WARNING, "AppManager: data flashing operation failed", .{});

                self.lastAction = action;

                // Return to confirmation state to allow user to retry or reset
                self.appState = .SelectionConfirmation;

                // Re-enable reset button after failed flash
                self.layout.emitEvent(
                    .{ .SpriteButtonEnabledChanged = .{ .target = .AppManagerResetAppButton, .enabled = true } },
                    .{ .excludeSelf = true },
                );

                Debug.log(.INFO, "AppManager: state reverted to {any} due to flash failure", .{self.appState});
            },
        }
    }

    /// Runs the main application loop.
    /// This is the primary entry point that orchestrates the entire application.
    /// It performs the following in order:
    ///
    /// 1. PATH RESOLUTION: Resolves user home directory for logs and preferences
    /// 2. MANAGER INITIALIZATION: Initializes all singleton managers in order
    /// 3. UI SETUP: Creates and configures the root UI layout
    /// 4. COMPONENT INITIALIZATION: Initializes and registers all application components
    /// 5. MAIN LOOP: Continuously updates and renders until window close
    ///
    /// All managers are initialized with proper error handling and deferred cleanup.
    /// The function blocks until the application window is closed by the user.
    ///
    /// `Errors`:
    ///   Various initialization errors from managers and components propagate up.
    ///   User receives OSD feedback for critical failures.
    fn run(self: *AppManager) !void {
        // Resolve file system paths relative to user home directory
        var logsPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
        const logsPath = fs.unwrapUserHomePath(&logsPathBuffer, AppConfig.MAIN_APP_LOGS_PATH) catch |err| {
            Debug.log(.ERROR, "Failed to resolve logs path: {any}", .{err});
            _ = osd.message("Failed to resolve logs directory path.", .{ .buttons = .ok, .level = .err });
            return err;
        };

        var prefsPathBuffer: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
        const prefsPath = fs.unwrapUserHomePath(&prefsPathBuffer, AppConfig.PREFERENCES_PATH) catch |err| {
            Debug.log(.ERROR, "Failed to resolve preferences path: {any}", .{err});
            _ = osd.message("Failed to resolve preferences directory path.", .{ .buttons = .ok, .level = .err });
            return err;
        };

        // ===================== SINGLETON MANAGERS ===========================
        // Initialize all singleton managers in dependency order.
        // Each manager is responsible for its own state and resources.
        // ========================================================================

        try Debug.init(self.allocator, .{ .standaloneLogFilePath = logsPath });
        defer Debug.deinit();
        Debug.log(.INFO, "Debug system initialized", .{});

        var isFirstAppLaunch = PreferencesManager.init(self.allocator, prefsPath) catch |err| {
            Debug.log(.ERROR, "Failed to initialize PreferencesManager: {any}", .{err});
            _ = osd.message("Failed to initialize application preferences.", .{ .buttons = .ok, .level = .err });
            return err;
        };
        defer PreferencesManager.deinit();
        Debug.log(.INFO, "PreferencesManager initialized (first launch: {})", .{isFirstAppLaunch});

        Debug.setLoggingSeverity(PreferencesManager.getDebugLevel() catch .INFO) catch |err| {
            Debug.log(.WARNING, "Failed to set logging severity: {any}", .{err});
        };

        try WindowManager.init();
        defer WindowManager.deinit();

        try ResourceManager.init(self.allocator);
        defer ResourceManager.deinit();

        try EventManager.init(self.allocator);
        defer EventManager.deinit();

        const shouldCheckUpdates = if (isFirstAppLaunch) true else (PreferencesManager.getCheckUpdates() catch false);
        try UpdateManager.init(
            self.allocator,
            shouldCheckUpdates,
            !isFirstAppLaunch,
        );
        defer UpdateManager.deinit();
        Debug.log(.INFO, "UpdateManager initialized (check updates: {})", .{shouldCheckUpdates});

        // ========================================================================
        // ===================== END SIGNLETON MANAGERS ===========================
        // ========================================================================

        // ============================ UI SETUP ==================================
        // Initialize global transform for all UI elements.
        // Init root layout and its children (AppManager-local UI only).
        // ========================================================================

        self.globalTransform = Transform{
            .x = 0,
            .y = 0,
            .w = WindowManager.getWindowWidth(),
            .h = WindowManager.getWindowHeight(),
            .size = .pixels(WindowManager.getWindowWidth(), WindowManager.getWindowHeight()),
            .position_ref = null,
            .size_ref = null,
            .relative = null,
            .relativeTransform = null,
        };
        self.globalTransform.resolve();

        var ui = UIChain.init(self.allocator);
        self.layout = try self.initLayout(&ui);
        defer self.layout.deinit();
        try self.layout.start();
        Debug.log(.INFO, "UI layout initialized and started", .{});

        // ========================================================================
        // ============================ END UI SETUP ==============================
        // ========================================================================

        // ============================ COMPONENTS INIT ===========================
        // Initialize main application components (which init their own children)
        // ========================================================================

        var componentRegistry = ComponentFramework.Registry.init(self.allocator);
        defer componentRegistry.deinit();

        var isoFilePicker = FilePicker.init(self.allocator) catch |err| {
            Debug.log(.ERROR, "Failed to initialize ISOFilePicker: {any}", .{err});
            _ = osd.message("Failed to initialize file picker component.", .{ .buttons = .ok, .level = .err });
            return err;
        };
        try componentRegistry.register(ComponentID.ISOFilePicker, @constCast(isoFilePicker.asComponentPtr()));
        try isoFilePicker.start();
        Debug.log(.DEBUG, "ISOFilePicker initialized", .{});

        var deviceList = DeviceList.init(self.allocator) catch |err| {
            Debug.log(.ERROR, "Failed to initialize DeviceList: {any}", .{err});
            _ = osd.message("Failed to initialize device list component.", .{ .buttons = .ok, .level = .err });
            return err;
        };
        try componentRegistry.register(ComponentID.DeviceList, @constCast(deviceList.asComponentPtr()));
        try deviceList.start();
        Debug.log(.DEBUG, "DeviceList initialized", .{});

        var dataFlasher = DataFlasher.init(self.allocator) catch |err| {
            Debug.log(.ERROR, "Failed to initialize DataFlasher: {any}", .{err});
            _ = osd.message("Failed to initialize data flasher component.", .{ .buttons = .ok, .level = .err });
            return err;
        };
        try componentRegistry.register(ComponentID.DataFlasher, @constCast(dataFlasher.asComponentPtr()));
        try dataFlasher.start();
        Debug.log(.DEBUG, "DataFlasher initialized", .{});

        var privilegedHelper = PrivilegedHelper.init(self.allocator) catch |err| {
            Debug.log(.ERROR, "Failed to initialize PrivilegedHelper: {any}", .{err});
            _ = osd.message("Failed to initialize privileged helper component.", .{ .buttons = .ok, .level = .err });
            return err;
        };
        try componentRegistry.register(ComponentID.PrivilegedHelper, @constCast(privilegedHelper.asComponentPtr()));
        try privilegedHelper.start();
        Debug.log(.DEBUG, "PrivilegedHelper initialized", .{});

        try componentRegistry.startAll();
        Debug.log(.INFO, "All components started successfully", .{});

        // ========================================================================
        // ============================ END COMPONENTS INIT =======================
        // ========================================================================

        const backgroundColor: rl.Color = Color.themeBg;
        const centerX: i32 = @intFromFloat(WindowManager.getWindowWidth() / 2);
        const centerY: i32 = @intFromFloat(WindowManager.getWindowHeight() / 2);
        const radius: f32 = WindowManager.getWindowWidth() / 2 + WindowManager.getWindowWidth() * 0.2;
        const innerColor: rl.Color = rl.Color.init(32, 32, 44, 255);
        const outerColor: rl.Color = Color.themeBg;

        Debug.log(.INFO, "Starting main application loop", .{});

        // ============================ MAIN APP LOOP ===========================
        // Continuously update and render until user closes window
        // ========================================================================

        while (!rl.windowShouldClose()) {
            // Update phase: process input and state changes
            try self.layout.update();
            UpdateManager.update();
            try componentRegistry.updateAll();

            // Render phase: draw all components
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(backgroundColor);
            rl.drawCircleGradient(centerX, centerY, radius, innerColor, outerColor);

            UI.BackgroundStars.draw();
            try self.layout.draw();

            UpdateManager.draw();
            try componentRegistry.drawAll();

            // Check for updates on first launch after initial frame
            if (isFirstAppLaunch) {
                const shouldUpdate = PreferencesManager.getCheckUpdatesPermission();
                if (shouldUpdate) {
                    UpdateManager.checkForUpdates();
                }
                isFirstAppLaunch = false;
            }
        }

        Debug.log(.INFO, "Application main loop ended, shutting down gracefully", .{});
    }

    /// Initializes the root UI layout hierarchy.
    /// Creates the main application UI structure including:
    ///   - Title and version text
    ///   - Background decorative graphics (rocket, satellite)
    ///   - "Start Over" reset button
    ///
    /// The layout is positioned relative to the global transform and adapts
    /// to the current window size.
    ///
    /// `Arguments`:
    ///   ui: UIChain builder instance for constructing the UI hierarchy
    ///
    /// `Returns`:
    ///   The root View containing all application UI elements
    ///
    /// `Errors`:
    ///   Propagates errors from UI builder operations
    fn initLayout(self: *AppManager, ui: *UIChain) !View {
        return try ui.view(.{
            .id = null,
            .position = .percent(0, 0),
            .size = .percent(1, 1),
            .relativeTransform = &self.globalTransform,
            .background = .{
                .transform = .{},
                .style = .{
                    .color = Color.transparent,
                    .borderStyle = .{ .color = Color.transparent },
                },
                .rounded = true,
                .bordered = true,
            },
        }).children(.{
            // Main application title
            ui.text("freetracer", .{
                .style = .{
                    .font = .JERSEY10_REGULAR,
                    .fontSize = 40,
                    .textColor = Color.white,
                },
            })
                .id("main_logo")
                .position(.percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, 0.035))
                .positionRef(.Parent)
                .sizeRef(.Parent),

            // Subtitle text positioned relative to logo
            ui.text("free and open-source by orbitixx", .{
                .style = .{
                    .font = .JERSEY10_REGULAR,
                    .fontSize = 18,
                    .textColor = Color.secondary,
                },
            })
                .position(.percent(0, 0.86))
                .positionRef(.{ .NodeId = "main_logo" })
                .sizeRef(.Parent),

            // Version display in top-right corner
            ui.text(AppConfig.APP_VERSION, .{
                .style = .{
                    .font = .JERSEY10_REGULAR,
                    .fontSize = 16,
                    .textColor = Color.secondary,
                },
            })
                .position(.percent(0.915, 0.051))
                .positionRef(.Parent)
                .sizeRef(.Parent),

            // Background decorative rocket graphic
            ui.texture(.ROCKET_GRAPHIC, .{})
                .position(.percent(0.4, 0.38))
                .positionRef(.Parent)
                .scale(2)
                .sizeRef(.Parent)
                .rotation(-33),

            // Background decorative satellite graphic (animates during workflow)
            ui.texture(.SATTELITE_GRAPHIC, .{})
                .elId(.AppManagerSatteliteGraphic)
                .position(.percent(0.7, 0.3))
                .positionRef(.Parent)
                .scale(3)
                .sizeRef(.Parent)
                .offsetToOrigin(),

            // "Start Over" button - resets application to initial state
            ui.spriteButton(.{
                .text = "Start Over",
                .texture = .BUTTON_FRAME_DANGER,
                .style = UIConfig.Styles.ResetAppButton,
            })
                .elId(.AppManagerResetAppButton)
                .position(.percent(AppConfig.APP_UI_MODULE_PANEL_FILE_PICKER_X, AppConfig.APP_UI_MODULE_PANEL_Y))
                .positionRef(.Parent)
                .size(.percent(0.13, 0.08))
                .callbacks(.{ .onClick = .{
                    .function = UIConfig.Callbacks.ResetAppButton.OnClick,
                    .context = self,
                } })
                .active(false),
        });
    }
};

/// UI Configuration - Callbacks and Styles for AppManager-local UI elements.
/// Contains all UI element callbacks and styling definitions used by local UI.
pub const UIConfig = struct {
    /// Event handler callbacks for UI elements
    pub const Callbacks = struct {
        /// Reset button callback handlers
        pub const ResetAppButton = struct {
            /// Handles reset button click event
            /// `Arguments`:
            ///   ctx: Opaque pointer to AppManager (cast at runtime)
            pub fn OnClick(ctx: *anyopaque) void {
                const appManager: *AppManager = @ptrCast(@alignCast(ctx));
                appManager.resetState();
            }
        };
    };

    /// Style definitions for all UI elements
    pub const Styles = struct {
        const ResetAppButton: UIFramework.SpriteButton.Style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 22,
            .textColor = Color.themeDanger,
            .tint = Color.themeDanger,
            .hoverTint = Color.themeSecondary,
            .hoverTextColor = Color.themeSecondary,
        };
    };
};
