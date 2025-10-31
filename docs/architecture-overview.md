# Freetracer Architecture Overview

This document summarizes the major pieces of the Freetracer codebase and how they fit together. It complements the high-level workflow in `CONTRIBUTING.md` and gives additional context to contributors working on deeper changes.

---

## Top-Level Layout

```
Freetracer (Main GUI Application)
├── src/
│   ├── main.zig                        Entry point and allocator setup
│   ├── managers/                       App-level singletons
│   │   ├── AppManager.zig              Main loop and lifecycle
│   │   ├── EventManager.zig            Event routing system
│   │   ├── WindowManager.zig           Window lifecycle (raylib)
│   │   └── ...
│   ├── components/                     Component hierarchy
│   │   ├── framework/                  Component base classes
│   │   ├── FilePicker/                 Select image file
│   │   ├── DeviceList/                 Select USB/SD target
│   │   ├── DataFlasher/                Flash request + process
│   │   └── macos/
│   │       └── PrivilegedHelper.zig    Manages privileged daemon & comms
│   └── ui/                             Rendering & UI elements
│
├── freetracer-lib/                     Shared library
│   └── src/
│       ├── ISOParser.zig               Parse ISO 9660 images
│       ├── macos/
│       │   ├── Mach.zig                XPC layer
│       │   ├── DiskArbitration.zig     Disk management (unmount, eject)
│       │   ├── IOKit.zig               IORegistry discovery (USB, SD cards)
│       │   └── FileSystem.zig          File/device handle utilities
│       └── util/                       Cross-cutting helpers
│
└── macos-helper/                       Privileged helper daemon
    └── src/
        ├── main.zig                    Helper entry point with main loop
        └── managers/
            └── ShutdownManager.zig     Graceful/error shutdown handling
```

---

## Component Model

Freetracer uses a component-based architecture with hierarchical event routing.

```
AppManager (main loop)
│
├─ FilePicker (logic)
│  └─ FilePickerUI (rendering)
│
├─ DeviceList (logic)
│  └─ DeviceListUI (rendering)
│
├─ DataFlasher (logic)
│  └─ DataFlasherUI (rendering)
│
└─ PrivilegedHelper (logic)
   └─ (runs in helper daemon via XPC)
```

- Each component implements the `Component` interface (`src/components/framework/Component.zig`).
- Components expose optional UI children; logic and UI talk via events.
- Communication flows through `EventManager`—components broadcast or signal events instead of calling each other directly.

### Event Flow

```
Component A (e.g., FilePicker)
    │
    ├─► EventManager.broadcast(event)
    │        │
    │        ├─► DeviceList.handleEvent(event)
    │        ├─► DataFlasher.handleEvent(event)
    │        └─► PrivilegedHelper.handleEvent(event)
    │
    └─► EventManager.signal("data_flasher", event)
             │
             └─► DataFlasher.handleEvent(event)  // targeted delivery
```

Typical flow:

1. User selects an image → `FilePicker` broadcasts `ImageSelected`.
2. `DeviceList` updates the drive view.
3. User picks a drive → `DeviceList` broadcasts `DeviceSelected`.
4. `DataFlasher` confirms and broadcasts `FlashRequested`.
5. `PrivilegedHelper` forwards the request via XPC to the helper daemon.
6. Helper writes the data, responds through XPC.
7. `PrivilegedHelper` broadcasts `FlashComplete`.
8. UI components update accordingly.

Key API entry points (`src/managers/EventManager.zig`):

- `subscribe(name, component)`
- `signal(name, event)`
- `broadcast(event)`
- `unsubscribe(name)`

---

## Inter-process Communication (XPC)

Privileged disk operations are handled via an Apple-recommended helper tool communicating over XPC:

```
GUI Application (unprivileged)
    │
    ├─ PrivilegedHelper component
    │   └─ XPCService (client mode)
    │        ├─ Creates Mach connection
    │        ├─ Sends request payload
    │        ├─ Validates response signature
    │        └─ Handles reply/cleanup
    │
    │ (Mach service: "com.orbitixx.freetracer")
    │
    └─ Helper Daemon (privileged)
        └─ XPCService (server mode)
             ├─ Listens on Mach service
             ├─ Validates client signature & bundle ID
             ├─ Performs disk operations
             └─ Returns status
```

Important security checks (`freetracer-lib/src/macos/Mach.zig`):

- Code signature verification (tamper detection)
- Bundle ID & Team ID validation (ensures trusted client)
- User ID checks (reject unintended escalations)
- Fail-safe defaults—deny on error

---

## Build Targets

The Zig build script (`build.zig`) defines dedicated targets for the shared library, privileged helper, and main app:

- `zig build bundle` — produces `Freetracer.app`
- `zig build test` — runs unit tests for the main app
- `zig build test-lib` — runs unit tests for `freetracer-lib`
- `zig build test-helper` — runs unit tests for the helper daemon

These targets are referenced from `CONTRIBUTING.md` but documented here for quick discovery.

---

Need an even deeper dive? Open an issue tagged `question` and a maintainer can help orient you. Contributions to this doc are welcome.
