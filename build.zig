const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = buildLibrary(b, target, optimize);
    _ = buildHelper(b, target, optimize);
    _ = buildMainApp(b, target, optimize);

    buildAppBundle(b);
}

fn buildLibrary(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib_mod = b.addModule("freetracer-lib", .{
        .root_source_file = b.path("freetracer-lib/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "freetracer-lib",
        .root_module = lib_mod,
    });

    lib.addCSourceFile(.{ .file = b.path("freetracer-lib/src/macos/xpc/xpc_helper.c") });
    lib.addCSourceFile(.{ .file = b.path("freetracer-lib/src/macos/cocoa/drag_hover.m"), .flags = &.{"-fobjc-arc"} });
    lib.addIncludePath(b.path("freetracer-lib/src/macos/xpc/"));

    lib.linkLibC();
    lib.linkFramework("IOKit");
    lib.linkFramework("CoreFoundation");
    lib.linkFramework("DiskArbitration");
    lib.linkFramework("ServiceManagement");
    lib.linkFramework("Security");
    lib.linkFramework("Cocoa");
    addMacOSSystemPaths(lib);

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const lib_test_step = b.step("test-lib", "Run freetracer-lib unit tests");
    lib_test_step.dependOn(&run_lib_unit_tests.step);

    return lib;
}

fn buildHelper(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const helper_mod = b.createModule(.{
        .root_source_file = b.path("macos-helper/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });

    const helper_exe = b.addExecutable(.{
        .name = "macos_helper",
        .root_module = helper_mod,
    });

    helper_exe.want_lto = false;
    helper_exe.link_gc_sections = false;

    const freetracer_lib_mod = b.modules.get("freetracer-lib").?;
    helper_exe.root_module.addImport("freetracer-lib", freetracer_lib_mod);

    b.installArtifact(helper_exe);

    const helper_unit_tests = b.addTest(.{
        .root_module = helper_mod,
    });

    const run_helper_unit_tests = b.addRunArtifact(helper_unit_tests);

    const helper_test_step = b.step("test-helper", "Run macos-helper unit tests");
    helper_test_step.dependOn(&run_helper_unit_tests.step);

    return helper_exe;
}

fn buildMainApp(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });

    const exe = b.addExecutable(.{
        .name = "freetracer",
        .root_module = exe_mod,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    const osdialog_dep = b.dependency("osdialog", .{});
    exe.root_module.addImport("osdialog", osdialog_dep.module("osdialog"));

    const freetracer_lib_mod = b.modules.get("freetracer-lib").?;
    exe.root_module.addImport("freetracer-lib", freetracer_lib_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    exe.step.dependOn(&run_exe_unit_tests.step);

    return exe;
}

fn buildAppBundle(b: *std.Build) void {
    const bundle_name = "Freetracer.app";
    const bundle_path = b.fmt("{s}", .{bundle_name});

    const bundle_step = b.step("bundle", "Create macOS app bundle");

    const mkdir_contents = b.addSystemCommand(&.{ "mkdir", "-p", b.fmt("{s}/Contents/MacOS", .{bundle_path}) });
    const mkdir_library = b.addSystemCommand(&.{ "mkdir", "-p", b.fmt("{s}/Contents/Library/LaunchServices", .{bundle_path}) });
    const mkdir_resources = b.addSystemCommand(&.{ "mkdir", "-p", b.fmt("{s}/Contents/Resources", .{bundle_path}) });

    const copy_main_exe = b.addSystemCommand(&.{
        "cp",
        b.getInstallPath(.bin, "freetracer"),
        b.fmt("{s}/Contents/MacOS/Freetracer", .{bundle_path}),
    });

    const copy_helper_exe = b.addSystemCommand(&.{
        "cp",
        b.getInstallPath(.bin, "macos_helper"),
        b.fmt("{s}/Contents/Library/LaunchServices/com.orbitixx.freetracer-helper", .{bundle_path}),
    });

    const copy_plist = b.addSystemCommand(&.{
        "cp",
        "macos/Info.plist",
        b.fmt("{s}/Contents/Info.plist", .{bundle_path}),
    });

    const copy_resources = b.addSystemCommand(&.{
        "cp",
        "-r",
        "src/resources/",
        b.fmt("{s}/Contents/Resources/", .{bundle_path}),
    });

    copy_main_exe.step.dependOn(&mkdir_contents.step);
    copy_main_exe.step.dependOn(b.getInstallStep());
    copy_helper_exe.step.dependOn(&mkdir_library.step);
    copy_helper_exe.step.dependOn(b.getInstallStep());
    copy_plist.step.dependOn(&mkdir_contents.step);
    copy_resources.step.dependOn(&mkdir_resources.step);

    bundle_step.dependOn(&copy_main_exe.step);
    bundle_step.dependOn(&copy_helper_exe.step);
    bundle_step.dependOn(&copy_plist.step);
    bundle_step.dependOn(&copy_resources.step);
}

fn addMacOSSystemPaths(step: *std.Build.Step.Compile) void {
    step.addSystemFrameworkPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    step.addSystemIncludePath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include" });
    step.addLibraryPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib" });
}
