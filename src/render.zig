//! All drawing. Reads the game state, never changes it (`*const Game`).

const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");
const Assets = @import("assets.zig").Assets;

const Game = game.Game;
const Bird = game.Bird;
const Color = rl.Color;
const Vector2 = rl.Vector2;

const sw: i32 = @intFromFloat(game.screen_w);
const sh: i32 = @intFromFloat(game.screen_h);

const word_font = 20;
const deg2rad = std.math.pi / 180.0;

const sky_top = Color.init(44, 92, 160, 255);
const sky_bottom = Color.init(160, 206, 238, 255);
const hill_back = Color.init(86, 150, 84, 255);
const hill_front = Color.init(60, 120, 64, 255);
const typed_color = Color.init(80, 230, 100, 255);
const target_color = Color.init(255, 214, 64, 255);
const gold = Color.init(255, 196, 40, 255);
const ice = Color.init(170, 225, 255, 255);

const bird_colors = [_]Color{
    Color.init(214, 72, 62, 255),
    Color.init(64, 104, 196, 255),
    Color.init(232, 160, 48, 255),
    Color.init(132, 84, 168, 255),
    Color.init(48, 150, 140, 255),
};

pub fn draw(g: *const Game, assets: *const Assets) void {
    drawBackground(g.clock);

    for (g.birds, 0..) |slot, i| {
        const b = slot orelse continue;
        drawBird(b, assets, g.target == i, g.clock);
    }
    // Labels in a second pass so they are always on top of every bird.
    for (g.birds, 0..) |slot, i| {
        const b = slot orelse continue;
        if (b.phase == .flying) drawLabel(b, g.target == i);
    }

    drawParticles(g);
    drawTurret(g);
    drawShot(g);
    drawPopups(g);

    if (g.freeze_timer > 0) rl.drawRectangle(0, 0, sw, sh, rl.fade(ice, 0.18));
    if (g.screen_flash > 0) rl.drawRectangle(0, 0, sw, sh, rl.fade(.white, g.screen_flash * 2));

    switch (g.state) {
        .menu => drawMenu(g),
        .playing => drawHud(g, assets),
        .game_over => {
            drawHud(g, assets);
            drawGameOver(g);
        },
    }
}

// ------------------------------------------------------------- helpers --

fn v(p: game.Vec2) Vector2 {
    return .{ .x = p.x, .y = p.y };
}

/// raylib wants C strings (`[:0]const u8`, a slice with a 0 byte after it).
/// This formats into a caller-provided stack buffer: no allocation.
fn fmtZ(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.mem.printSentinel(buf, fmt, args, 0) catch "?";
}

fn drawCentered(text: [:0]const u8, y: i32, size: i32, color: Color) void {
    rl.drawText(text, @divTrunc(sw - rl.measureText(text, size), 2), y, size, color);
}

fn drawCenteredAt(text: [:0]const u8, cx: i32, y: i32, size: i32, color: Color) void {
    rl.drawText(text, cx - @divTrunc(rl.measureText(text, size), 2), y, size, color);
}

/// raylib only fills triangles given counter-clockwise (on screen). Our bird
/// gets mirrored when flying left, which flips winding, so fix it up here.
fn triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) void {
    const cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (cross > 0) rl.drawTriangle(a, c, b, color) else rl.drawTriangle(a, b, c, color);
}

/// Scrolls `base` to the right at `speed` px/s, wrapping within [lo, lo + period).
fn scrollX(base: f32, speed: f32, time: f32, lo: f32, period: f32) f32 {
    return lo + @mod(base + speed * time - lo, period);
}

// ---------------------------------------------------------- background --

fn drawBackground(time: f32) void {
    rl.drawRectangleGradientV(0, 0, sw, sh, sky_top, sky_bottom);
    rl.drawCircle(680, 90, 40, Color.init(255, 236, 160, 255));

    // Parallax: far things move slower than near things.
    drawCloudLayer(time, 6, 7, 0.6, 0.45, 60);
    drawCloudLayer(time, 4, 18, 1.0, 0.8, 130);

    // Far hills scroll slowly. The wrap range is wider than the screen plus
    // a hill's visible width, so hills never pop in or out on screen.
    for (0..3) |i| {
        const x = scrollX(@as(f32, @floatFromInt(i)) * 480, 6, time, -320, 1440);
        rl.drawCircle(@intFromFloat(x), sh + 260, 380, hill_back);
    }
    rl.drawCircle(420, sh + 340, 400, hill_front);
}

fn drawCloudLayer(time: f32, count: usize, speed: f32, scale: f32, alpha: f32, y_base: f32) void {
    const period = game.screen_w + 240;
    for (0..count) |i| {
        const fi: f32 = @floatFromInt(i);
        const x = scrollX(fi * period / @as(f32, @floatFromInt(count)), speed, time, -120, period);
        // Cheap "random" heights that stay the same every frame.
        const y = y_base + @mod(fi * 53, 90);
        drawCloud(.{ .x = x, .y = y }, scale, rl.fade(.white, alpha));
    }
}

fn drawCloud(at: Vector2, s: f32, color: Color) void {
    rl.drawCircleV(.{ .x = at.x - 28 * s, .y = at.y + 6 * s }, 20 * s, color);
    rl.drawCircleV(.{ .x = at.x, .y = at.y - 6 * s }, 28 * s, color);
    rl.drawCircleV(.{ .x = at.x + 30 * s, .y = at.y + 4 * s }, 22 * s, color);
    rl.drawRectangleRounded(.{ .x = at.x - 48 * s, .y = at.y, .width = 96 * s, .height = 26 * s }, 1, 8, color);
}

// ---------------------------------------------------------------- bird --

fn drawBird(b: Bird, assets: *const Assets, targeted: bool, time: f32) void {
    const center = v(b.pos);

    if (b.power != null and b.phase == .flying) {
        const pulse = 0.25 + 0.15 * @sin(time * 8);
        rl.drawCircleV(center, 34, rl.fade(gold, pulse));
    }
    if (targeted) {
        rl.drawCircleLinesV(center, 30, target_color);
        rl.drawCircleLinesV(center, 31, target_color);
    }

    // `if (optional) |value|`: use the sprite only if it was loaded.
    if (assets.bird) |tex| {
        const frames: f32 = @floatFromInt(assets.bird_frames);
        const fw = @as(f32, @floatFromInt(tex.width)) / frames;
        const h: f32 = @floatFromInt(tex.height);
        const frame: f32 = if (b.phase == .flying) @mod(@floor(b.age * 10), frames) else 0;
        const scale = 64 / h;
        // A negative source width mirrors the sprite horizontally.
        const src = rl.Rectangle.init(frame * fw, 0, if (b.dir > 0) fw else -fw, h);
        const dst = rl.Rectangle.init(center.x, center.y, fw * scale, h * scale);
        const tint: Color = if (b.power != null) gold else .white;
        rl.drawTexturePro(tex, src, dst, .{ .x = dst.width / 2, .y = dst.height / 2 }, b.angle, tint);
        return;
    }

    drawBirdShape(b);
}

/// A bird made of circles and triangles. Points are given in "bird space"
/// (facing right, centered on the body), then mirrored and rotated.
fn drawBirdShape(b: Bird) void {
    const body = if (b.power != null) gold else bird_colors[b.word[0] % bird_colors.len];
    const dark = Color.init(body.r / 2, body.g / 2, body.b / 2, 255);

    // A struct with only functions works as a local namespace: Zig has no
    // closures, so we pass the bird along explicitly.
    const P = struct {
        fn at(bird: Bird, x: f32, y: f32) Vector2 {
            const local = Vector2.init(x * bird.dir, y).rotate(bird.angle * deg2rad);
            return local.add(v(bird.pos));
        }
    };

    const flap: f32 = if (b.phase == .flying) @sin(b.age * 14) else 0.6;

    // tail
    triangle(P.at(b, -12, -2), P.at(b, -30, -12), P.at(b, -28, 8), dark);
    // body + head
    rl.drawCircleV(P.at(b, 0, 0), 16, body);
    rl.drawCircleV(P.at(b, 15, -9), 10, body);
    // beak
    triangle(P.at(b, 23, -12), P.at(b, 33, -8), P.at(b, 23, -5), Color.init(250, 190, 40, 255));
    // eye (an X when shot)
    const eye = P.at(b, 18, -11);
    if (b.phase == .flying) {
        rl.drawCircleV(eye, 3, .white);
        rl.drawCircleV(P.at(b, 19, -11), 1.6, .black);
    } else {
        rl.drawLineEx(.{ .x = eye.x - 3, .y = eye.y - 3 }, .{ .x = eye.x + 3, .y = eye.y + 3 }, 2, .black);
        rl.drawLineEx(.{ .x = eye.x - 3, .y = eye.y + 3 }, .{ .x = eye.x + 3, .y = eye.y - 3 }, 2, .black);
    }
    // wing, flapping up and down
    triangle(P.at(b, -8, -2), P.at(b, 8, -2), P.at(b, -4, -2 - 22 * flap), dark);
}

fn drawLabel(b: Bird, targeted: bool) void {
    var typed_buf: [16]u8 = undefined;
    var rest_buf: [16]u8 = undefined;
    const typed = fmtZ(&typed_buf, "{s}", .{b.word[0..b.typed]});
    const rest = fmtZ(&rest_buf, "{s}", .{b.word[b.typed..]});

    const typed_w = rl.measureText(typed, word_font);
    const total_w = typed_w + rl.measureText(rest, word_font);

    const pad = 6;
    const cx: i32 = @intFromFloat(b.pos.x);
    const top: i32 = @as(i32, @intFromFloat(b.pos.y)) - 52;
    const x0 = cx - @divTrunc(total_w, 2);

    const box = rl.Rectangle.init(
        @floatFromInt(x0 - pad),
        @floatFromInt(top - 3),
        @floatFromInt(total_w + 2 * pad),
        word_font + 6,
    );
    rl.drawRectangleRounded(box, 0.4, 6, rl.fade(.black, 0.6));
    if (targeted) {
        rl.drawRectangleRoundedLinesEx(box, 0.4, 6, 2, target_color);
    } else if (b.power != null) {
        rl.drawRectangleRoundedLinesEx(box, 0.4, 6, 2, gold);
    }

    if (b.power) |p| drawCenteredAt(p.name(), cx, top - 20, 14, gold);

    const flashing = b.flash > 0;
    rl.drawText(typed, x0, top, word_font, if (flashing) .red else typed_color);
    rl.drawText(rest, x0 + typed_w, top, word_font, if (flashing) .red else .white);
}

// -------------------------------------------------------------- effects --

fn drawParticles(g: *const Game) void {
    for (g.particles) |slot| {
        const p = slot orelse continue;
        const alpha = std.math.clamp(p.life / p.max_life, 0, 1);
        const rec = rl.Rectangle.init(p.pos.x, p.pos.y, 10, 4);
        rl.drawRectanglePro(rec, .{ .x = 5, .y = 2 }, p.angle, rl.fade(.white, alpha));
    }
}

fn drawPopups(g: *const Game) void {
    var buf: [32]u8 = undefined;
    for (g.popups) |slot| {
        const p = slot orelse continue;
        const alpha = std.math.clamp(p.life / game.popup_time, 0, 1);
        // `switch` on a tagged union; `|value|` captures the active payload.
        const text: [:0]const u8, const color: Color, const size: i32 = switch (p.text) {
            .points => |points| .{ fmtZ(&buf, "+{d}", .{points}), .white, 20 },
            .power => |power| .{ power.name(), gold, 26 },
            .extra_life => .{ "EXTRA LIFE!", typed_color, 26 },
        };
        const x: i32 = @intFromFloat(p.pos.x);
        const y: i32 = @intFromFloat(p.pos.y);
        drawCenteredAt(text, x + 1, y + 1, size, rl.fade(.black, alpha * 0.6));
        drawCenteredAt(text, x, y, size, rl.fade(color, alpha));
    }
}

fn drawShot(g: *const Game) void {
    const s = g.shot orelse return;
    const t = s.timer / game.shot_time; // 1 -> 0 as it fades
    rl.drawLineEx(v(s.from), v(s.to), 2 + 4 * t, rl.fade(Color.init(255, 250, 180, 255), t));
    rl.drawCircleV(v(s.to), 10 + 30 * (1 - t), rl.fade(.yellow, t * 0.8));
    rl.drawCircleV(v(s.from), 12 * t, rl.fade(.white, t));
}

fn drawTurret(g: *const Game) void {
    const base = v(game.turret);
    // Aim at the locked bird if there is one, otherwise straight up.
    var aim = Vector2.init(0, -1);
    if (g.target) |i| {
        if (g.birds[i]) |b| {
            const d = v(b.pos).subtract(base);
            const len = @sqrt(d.x * d.x + d.y * d.y);
            if (len > 0) aim = d.scale(1 / len);
        }
    }
    rl.drawLineEx(base, base.add(aim.scale(34)), 10, Color.init(50, 50, 60, 255));
    rl.drawCircleV(base, 20, Color.init(70, 70, 84, 255));
    rl.drawRectangle(@as(i32, @intFromFloat(base.x)) - 30, sh - 14, 60, 14, Color.init(40, 40, 48, 255));
}

// ------------------------------------------------------------------ UI --

fn drawHud(g: *const Game, assets: *const Assets) void {
    var buf: [64]u8 = undefined;
    rl.drawRectangle(0, 0, sw, 36, rl.fade(.black, 0.4));

    rl.drawText(fmtZ(&buf, "Score {d}", .{g.stats.score}), 12, 8, 20, .white);

    // Lives as little red dots; grey dots show lives already lost.
    rl.drawText("Lives", 165, 8, 20, .white);
    const slots = @max(g.lives, g.mode.params().lives);
    for (0..slots) |i| {
        const x: f32 = 232 + @as(f32, @floatFromInt(i)) * 16;
        const alive = i < g.lives;
        rl.drawCircleV(.{ .x = x, .y = 18 }, 6, if (alive) .red else rl.fade(.gray, 0.5));
    }

    const combo = g.stats.combo();
    const combo_color: Color = if (combo >= game.max_combo) .gold else if (combo > 1) .orange else .white;
    rl.drawText(fmtZ(&buf, "Combo x{d}", .{combo}), 335, 8, 20, combo_color);

    rl.drawText(fmtZ(&buf, "WPM {d:.0}", .{g.stats.wpm()}), 475, 8, 20, .white);
    rl.drawText(fmtZ(&buf, "Lv {d}", .{g.level() + 1}), 580, 8, 20, .white);
    rl.drawText(fmtZ(&buf, "Best {d}", .{g.highScore()}), 650, 8, 20, .light_gray);

    if (g.freeze_timer > 0) {
        drawCentered(fmtZ(&buf, "FROZEN {d:.1}s", .{g.freeze_timer}), 46, 22, ice);
    }

    rl.drawText("Backspace/Esc: unlock", 10, sh - 22, 16, rl.fade(.white, 0.7));
    const music_hint = fmtZ(&buf, "{s} | Tab: music {s}", .{
        g.mode.name(),
        if (assets.music_on) "on" else "off",
    });
    rl.drawText(music_hint, sw - 10 - rl.measureText(music_hint, 16), sh - 22, 16, rl.fade(.white, 0.7));
}

fn drawMenu(g: *const Game) void {
    var buf: [96]u8 = undefined;
    rl.drawRectangle(0, 0, sw, sh, rl.fade(.black, 0.35));
    drawCentered("BIRD TYPER", 90, 64, .white);
    drawCentered("Type the word on a bird to shoot it down.", 180, 20, .white);
    drawCentered("Golden birds give FREEZE, BOMB or +1 LIFE.", 208, 20, gold);
    drawCentered("Extra life every 5000 points.", 236, 20, .white);

    // Mode picker: one box per mode, the selected one highlighted.
    const tags = std.meta.tags(game.Mode);
    for (tags, 0..) |mode, i| {
        const cx: i32 = 220 + @as(i32, @intCast(i)) * 180;
        const selected = mode == g.mode;
        const box = rl.Rectangle.init(@floatFromInt(cx - 75), 290, 150, 44);
        rl.drawRectangleRounded(box, 0.3, 6, rl.fade(.black, if (selected) 0.6 else 0.3));
        if (selected) rl.drawRectangleRoundedLinesEx(box, 0.3, 6, 3, target_color);
        const label = fmtZ(&buf, "{d}  {s}", .{ i + 1, mode.name() });
        drawCenteredAt(label, cx, 302, 22, if (selected) target_color else .light_gray);
    }
    const p = g.mode.params();
    drawCentered(fmtZ(&buf, "{d} lives, speed x{d:.2}  -  Left/Right or 1-3 to choose", .{ p.lives, p.speed_mult }), 350, 18, .light_gray);

    drawCentered("Press ENTER to start", 400, 30, target_color);
    drawCentered(fmtZ(&buf, "Best ({s}): {d}", .{ g.mode.name(), g.highScore() }), 450, 20, .light_gray);
}

fn drawGameOver(g: *const Game) void {
    var buf: [96]u8 = undefined;
    const s = g.stats;
    rl.drawRectangle(0, 0, sw, sh, rl.fade(.black, 0.6));
    drawCentered("GAME OVER", 80, 56, .red);
    drawCentered(fmtZ(&buf, "{s} mode", .{g.mode.name()}), 140, 20, .light_gray);
    drawCentered(fmtZ(&buf, "Score: {d}", .{s.score}), 180, 30, .white);
    drawCentered(fmtZ(&buf, "WPM: {d:.1}", .{s.wpm()}), 225, 24, .white);
    drawCentered(fmtZ(&buf, "Accuracy: {d:.1}%", .{s.accuracy()}), 260, 24, .white);
    drawCentered(fmtZ(&buf, "Birds shot: {d}", .{s.words_killed}), 295, 24, .white);

    // Per-letter stats: up to 3 worst letters with their miss counts.
    var letters_buf: [3]u8 = undefined;
    const worst = s.mostMissed(&letters_buf);
    if (worst.len == 0) {
        drawCentered("No missed letters!", 335, 22, typed_color);
    } else {
        var line_buf: [64]u8 = undefined;
        var w: std.Io.Writer = .fixed(&line_buf);
        w.writeAll("Most missed:") catch {};
        for (worst) |c| w.print("  {c} ({d})", .{ c, s.missed[c - 'a'] }) catch {};
        drawCentered(fmtZ(&buf, "{s}", .{w.buffered()}), 335, 22, .orange);
    }

    if (g.new_record) {
        drawCentered("NEW HIGH SCORE!", 385, 28, .gold);
    } else {
        drawCentered(fmtZ(&buf, "Best: {d}", .{g.highScore()}), 385, 24, .light_gray);
    }
    drawCentered("ENTER: play again    Backspace: menu", 450, 24, target_color);
}
