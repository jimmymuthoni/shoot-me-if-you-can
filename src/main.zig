const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");
const render = @import("render.zig");
const highscore = @import("highscore.zig");
const Assets = @import("assets.zig").Assets;

/// Opens the window, loads assets and runs the game loop until the window closes.
pub fn main(init: std.process.Init) !void {
    const io = init.io;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(@intFromFloat(game.screen_w), @intFromFloat(game.screen_h), "Bird Typer");
    defer rl.closeWindow();
    rl.setTargetFPS(60);
    rl.setExitKey(.null);

    var assets = Assets.load();
    defer assets.unload();

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));

    var g = game.Game.init(seed, highscore.load(io));

    while (!rl.windowShouldClose()) {
        const dt = @min(rl.getFrameTime(), 0.1);

        if (rl.isKeyPressed(.tab)) assets.toggleMusic();
        assets.updateMusic();

        const was_playing = g.state == .playing;
        g.update(dt, readInput());
        if (was_playing and g.state == .game_over and g.new_record) {
            highscore.save(io, g.high_scores);
        }

        var sounds = g.sounds.iterator();
        while (sounds.next()) |id| {
            const pitch: f32 = if (id == .hit) 1 + 0.12 * @as(f32, @floatFromInt(g.hit_combo - 1)) else 1;
            assets.play(id, pitch);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        render.draw(&g, &assets);
    }
}

/// Collects this frame's typed letters and special keys into an Input.
fn readInput() game.Input {
    var input: game.Input = .{};
    var ch = rl.getCharPressed();
    while (ch > 0) : (ch = rl.getCharPressed()) {
        if (ch < 128) input.pushChar(@intCast(ch));
    }
    input.enter = rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter);
    input.unlock = rl.isKeyPressed(.backspace) or rl.isKeyPressed(.escape);
    input.left = rl.isKeyPressed(.left);
    input.right = rl.isKeyPressed(.right);
    return input;
}

// Pulls the other files' tests into `zig build test`.
test {
    _ = game;
    _ = highscore;
    _ = @import("synth.zig");
}
