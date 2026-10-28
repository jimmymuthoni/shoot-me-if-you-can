const std = @import("std");

// `zig build` runs this function to build a graph of steps; it doesn't
// compile anything itself. The build runner then executes the steps you ask for.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The dependency named `.raylib_zig` in build.zig.zon (added by `zig fetch --save`).
    // raylib-zig compiles raylib's C sources itself, so no system raylib is needed.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    // The "raylib" module already links the compiled raylib C library.
    const raylib = raylib_dep.module("raylib");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // Makes `@import("raylib")` work in our sources.
        .imports = &.{.{ .name = "raylib", .module = raylib }},
    });

    const exe = b.addExecutable(.{
        .name = "bird_typer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // zig build run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);

    // zig build test  (game.zig and words.zig tests, reached via main.zig)
    const tests = b.addTest(.{ .root_module = exe_mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
