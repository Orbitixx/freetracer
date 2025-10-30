//! Freetracer Library - Shared Code Interface
//!
//! This module serves as the central export surface for the freetracer library,
//! providing shared functionality and types used by both the GUI application and
//! the privileged helper process.
//!
//! The library is organized into several logical subsystems:
//!
//! **Utilities**
//!   - Debug: Logging and debugging utilities
//!   - String: String manipulation and formatting
//!   - Time: Timestamp and duration utilities
//!   - Endian: Byte order conversion
//!   - Device: Device enumeration and detection
//!
//! **macOS Integration**
//!   - FileSystem: Home directory resolution and path utilities
//!   - Permissions: macOS permission checking and elevation
//!   - DiskArbitration: Disk and volume management via DADisk framework
//!   - Mach: Low-level Mach kernel APIs
//!   - IOKit: Hardware and device information APIs
//!
//! **Data Processing**
//!   - ISO9660: ISO 9660 filesystem parsing and validation
//!   - ISOParser: High-level ISO image analysis
//!   - Types: Shared type definitions (StorageDevice, etc.)
//!
//! **Inter-Process Communication**
//!   - XPC: Generated C bindings for XPC services (GUI ↔ Privileged Helper)
//!
//! Downstream code imports this module to access all canonical types and subsystems
//! without depending on individual file paths, providing a stable API surface.

const std = @import("std");
const testing = std.testing;

/// Platform check: true if compiling for macOS
const isMacOS = (@import("builtin").os.tag == .macos);

/// C XPC helper bindings for inter-process communication
/// Used by both the GUI application and privileged helper for secure IPC
const c_xpc = @cImport(@cInclude("xpc_helper.h"));

// ============================================================================
// UTILITIES - Generic helper functions and data structures
// ============================================================================

/// Application-wide constants and configuration values
pub const constants = @import("./constants.zig");

/// Debug logging and debugging utilities (singleton)
const debug = @import("./util/debug.zig");

/// Shared type definitions across the library
pub const types = @import("./types.zig");

/// Time utilities: timestamps, duration calculations, conversions
pub const time = @import("./util/time.zig");

/// String manipulation and formatting utilities
pub const string = @import("./util/string.zig");

/// Device enumeration and hardware detection utilities
pub const device = @import("./util/device.zig");

/// Byte order conversion and endianness utilities
pub const endian = @import("./util/endian.zig");

// ============================================================================
// macOS INTEGRATION - System framework bindings and utilities
// ============================================================================

/// File system utilities and path resolution
/// Handles user home directory expansion and path validation
pub const fs = @import("./macos/FileSystem.zig");

/// macOS permission checking and privilege elevation
/// Validates user permissions and manages authorization flows
pub const MacOSPermissions = @import("./macos/Permissions.zig");

/// Disk Arbitration framework interface
/// Provides access to mounted volumes and storage device information
pub const DiskArbitration = @import("./macos/DiskArbitration.zig");

/// Low-level Mach kernel interface
/// Direct access to Mach APIs for advanced system operations
pub const Mach = @import("./macos/Mach.zig");

/// IOKit framework interface
/// Hardware device information and device tree traversal
pub const IOKit = @import("./macos/IOKit.zig");

// ============================================================================
// DATA PROCESSING - File format parsing and analysis
// ============================================================================

/// ISO 9660 filesystem format parsing
/// Parses ISO image headers and validates file system structure
pub const iso9660 = @import("./util/iso9660.zig");

/// High-level ISO image file parser
/// Analyzes ISO images and extracts useful metadata
pub const ISOParser = @import("./ISOParser.zig");

// ============================================================================
// TYPE EXPORTS - Canonical types used throughout the library
// ============================================================================

/// C type definitions and foreign function interface bindings
pub const c = types.c;

/// Storage device representation
/// Used by both GUI and privileged helper to describe target devices
pub const StorageDevice = types.StorageDevice;

// ============================================================================
// SINGLETONS - Library-wide shared state
// ============================================================================

/// Debug logging singleton (global access)
/// Available to all consumers for consistent logging behavior
pub const Debug = debug;

/// String utilities singleton (global access)
pub const String = string;

// ============================================================================
// IPC - Inter-Process Communication
// ============================================================================

/// XPC service bindings for GUI ↔ Privileged Helper communication
/// Generated C bindings providing type-safe XPC message interface
pub const xpc = c_xpc;
