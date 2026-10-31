//! Tiny software synthesizer: builds the default sound effects and the
//! background music loop as 16-bit mono samples. No raylib in here, so the
//! output can be tested; assets.zig turns the samples into raylib sounds.
//! Any file in assets/ replaces the matching generated sound.

const std = @import("std");
const SoundId = @import("game.zig").SoundId;

pub const sample_rate = 22050;
pub const music_seconds = 8;
/// Large enough for the longest thing we generate (the music loop).
pub const max_samples = music_seconds * sample_rate;

const Waveform = enum { sine, square, triangle, noise };

/// Mixes (adds) one note into `buf`. The pitch slides from `f0` to `f1` Hz,
/// and the volume fades out linearly after a 5 ms attack, so there are no clicks.
fn addTone(buf: []i16, start_s: f32, dur_s: f32, f0: f32, f1: f32, wave: Waveform, vol: f32) void {
    const start: usize = @intFromFloat(start_s * sample_rate);
    const len: usize = @intFromFloat(dur_s * sample_rate);
    const len_f: f32 = @floatFromInt(len);
    var phase: f32 = 0;
    var noise: u32 = 0x9E3779B9;

    for (0..len) |i| {
        const idx = start + i;
        if (idx >= buf.len) break;
        const i_f: f32 = @floatFromInt(i);
        const t = i_f / len_f;

        phase += (f0 + (f1 - f0) * t) / sample_rate;
        phase -= @floor(phase); // keep it in 0..1

        // `switch` is an expression, so it can produce the sample value.
        const s: f32 = switch (wave) {
            .sine => @sin(phase * std.math.tau),
            .square => if (phase < 0.5) 1 else -1,
            .triangle => 4 * @abs(phase - 0.5) - 1,
            .noise => blk: {
                // xorshift32: a tiny pseudo-random generator
                noise ^= noise << 13;
                noise ^= noise >> 17;
                noise ^= noise << 5;
                break :blk @as(f32, @floatFromInt(noise)) / 2147483648.0 - 1;
            },
        };

        const attack = @min(1, i_f / (0.005 * sample_rate));
        const mixed = @as(f32, @floatFromInt(buf[idx])) + s * attack * (1 - t) * vol * 32767;
        buf[idx] = @intFromFloat(std.math.clamp(mixed, -32768, 32767));
    }
}

/// Renders one sound effect into `buf` and returns the used part.
pub fn effect(id: SoundId, buf: []i16) []i16 {
    const seconds: f32 = switch (id) {
        .shoot => 0.07,
        .hit => 0.3,
        .miss => 0.2,
        .game_over => 1.1,
        .powerup => 0.45,
    };
    const out = buf[0..@intFromFloat(seconds * sample_rate)];
    @memset(out, 0);

    switch (id) {
        .shoot => addTone(out, 0, 0.07, 1100, 600, .square, 0.12),
        .hit => {
            addTone(out, 0, 0.12, 0, 0, .noise, 0.35);
            addTone(out, 0, 0.3, 700, 180, .sine, 0.5);
        },
        .miss => addTone(out, 0, 0.2, 170, 120, .square, 0.18),
        .game_over => {
            // Three falling notes: A4, F4, C4.
            for ([_]f32{ 440.0, 349.23, 261.63 }, 0..) |freq, i| {
                const at = @as(f32, @floatFromInt(i)) * 0.35;
                addTone(out, at, 0.4, freq, freq, .triangle, 0.5);
            }
        },
        .powerup => {
            // Rising arpeggio: C5 E5 G5 C6.
            for ([_]f32{ 523.25, 659.25, 783.99, 1046.5 }, 0..) |freq, i| {
                const at = @as(f32, @floatFromInt(i)) * 0.09;
                addTone(out, at, 0.15, freq, freq, .square, 0.12);
            }
        },
    }
    return out;
}

/// An 8-second loop: bass plus an arpeggio over Am - F - C - G.
pub fn music(buf: []i16) []i16 {
    const out = buf[0..max_samples];
    @memset(out, 0);

    const step: f32 = 0.25; // one eighth note at 120 BPM
    const Chord = struct { bass: f32, notes: [3]f32 };
    const chords = [_]Chord{
        .{ .bass = 110.0, .notes = .{ 440.0, 523.25, 659.25 } }, // Am
        .{ .bass = 87.31, .notes = .{ 349.23, 440.0, 523.25 } }, // F
        .{ .bass = 130.81, .notes = .{ 392.0, 523.25, 659.25 } }, // C
        .{ .bass = 98.0, .notes = .{ 392.0, 493.88, 587.33 } }, // G
    };
    const pattern = [_]usize{ 0, 1, 2, 1, 0, 1, 2, 1 };

    for (chords, 0..) |chord, c| {
        const bar = @as(f32, @floatFromInt(c)) * step * pattern.len;
        for (pattern, 0..) |note, s| {
            const at = bar + @as(f32, @floatFromInt(s)) * step;
            if (s % 2 == 0) addTone(out, at, step * 1.8, chord.bass, chord.bass, .triangle, 0.22);
            addTone(out, at, step * 0.9, chord.notes[note], chord.notes[note], .square, 0.045);
        }
    }
    return out;
}

test "every effect is non-silent and fits the buffer" {
    var buf: [max_samples]i16 = undefined;
    for (std.meta.tags(SoundId)) |id| {
        const samples = effect(id, &buf);
        try std.testing.expect(samples.len > 0 and samples.len <= max_samples);
        var peak: i16 = 0;
        for (samples) |s| peak = @max(peak, s);
        try std.testing.expect(peak > 1000);
    }
}

test "music fills the whole loop" {
    var buf: [max_samples]i16 = undefined;
    const samples = music(&buf);
    try std.testing.expectEqual(@as(usize, max_samples), samples.len);
    // The last bar should still have sound in it.
    var peak: i16 = 0;
    for (samples[max_samples - sample_rate ..]) |s| peak = @max(peak, s);
    try std.testing.expect(peak > 1000);
}
