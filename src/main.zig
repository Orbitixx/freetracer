const std = @import("std");
const debug = @import("lib/util/debug.zig");
const strings = @import("lib/util/strings.zig");
const rl = @import("raylib");

const assert = std.debug.assert;

const IsoParser = @import("modules/IsoParser.zig");
const IsoWriter = @import("modules/IsoWriter.zig");

const ArgValidator = struct {
    isoPath: bool = false,
    devicePath: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    debug.printf("\nTotal process arguments: {d}\n", .{args.len});

    const screenWidth = 800;
    const screenHeight = 500;

    rl.initWindow(screenWidth, screenHeight, "");
    defer rl.closeWindow(); // Close window and OpenGL context
    //
    const backgroundColor: rl.Color = .{ .r = 29, .g = 44, .b = 64, .a = 100 };

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        const SCREEN_HEIGHT: f32 = @floatFromInt(rl.getScreenHeight());
        const SCREEN_WIDTH: f32 = @floatFromInt(rl.getScreenWidth());
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(backgroundColor);
        rl.drawRectangle(560, 0, @intFromFloat(SCREEN_WIDTH - 500), @intFromFloat(SCREEN_HEIGHT), .fade(.light_gray, 0.3));

        rl.drawText("freetracer", @intFromFloat(SCREEN_WIDTH * 0.1), @intFromFloat(SCREEN_HEIGHT * 0.1), 20, .light_gray);
        //----------------------------------------------------------------------------------
    }

    // var argValidator = ArgValidator{};
    //
    // var isoPath: []u8 = undefined;
    // var devicePath: []u8 = undefined;
    //
    // const ISO_ARG = "--iso";
    // const DEVICE_ARG = "--device";
    //
    // for (1..(args.len - 1)) |i| {
    //     assert(args[i + 1].len != 0);
    //
    //     if (strings.eql(args[i], ISO_ARG)) {
    //         isoPath = args[i + 1];
    //         argValidator.isoPath = true;
    //     } else if (strings.eql(args[i], DEVICE_ARG)) {
    //         devicePath = args[i + 1];
    //         argValidator.devicePath = true;
    //     }
    // }
    //
    // debug.printf("\n--iso: {s}\n--device: {s}", .{ isoPath, devicePath });
    //
    // assert(argValidator.isoPath == true and argValidator.devicePath == true);
    //
    // try IsoParser.parseIso(&allocator, isoPath);
    // try IsoWriter.write(isoPath, devicePath);
    //
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/alpine.iso");
    // try IsoParser.parseIso(&allocator, "/Users/cerberus/Documents/Projects/freetracer/tinycore.iso");

    debug.print("\n");
}
