//! High scores per difficulty mode, stored in a small text file:
//!
//!     easy 1200
//!     normal 3400
//!     hard 800
//!
//! A file holding one bare number (the format of the first version) is read
//! as the Normal score, so old high scores survive the upgrade.

const std = @import("std");
const Mode = @import("game.zig").Mode;

pub const Scores = std.EnumArray(Mode, u32);
pub const path = "highscore.txt";

/// A missing or garbled file just means "no high scores yet".
pub fn load(io: std.Io) Scores {
    var buf: [256]u8 = undefined;
    // `catch return ...`: on any error (FileNotFound, ...) bail out early.
    const text = std.Io.Dir.cwd().readFile(io, path, &buf) catch return .initFill(0);
    return parse(text);
}

pub fn save(io: std.Io, scores: Scores) void {
    var buf: [256]u8 = undefined;
    // Three short lines always fit in 256 bytes.
    const text = format(&buf, scores) catch unreachable;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch |err| {
        std.log.warn("could not save high scores: {t}", .{err});
    };
}

pub fn parse(text: []const u8) Scores {
    var scores: Scores = .initFill(0);
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const first = parts.next() orelse continue;
        if (parts.next()) |number| {
            // "normal 3400": stringToEnum maps the text to a Mode, or null.
            const mode = std.meta.stringToEnum(Mode, first) orelse continue;
            scores.set(mode, std.fmt.parseInt(u32, number, 10) catch continue);
        } else {
            // Old format: just a number.
            scores.set(.normal, std.fmt.parseInt(u32, first, 10) catch continue);
        }
    }
    return scores;
}

/// Writes into `buf` and returns the written part.
pub fn format(buf: []u8, scores: Scores) std.Io.Writer.Error![]u8 {
    // A Writer over a fixed buffer: the 0.15+ replacement for fixedBufferStream.
    var w: std.Io.Writer = .fixed(buf);
    for (std.meta.tags(Mode)) |mode| {
        // `{t}` prints an enum's tag name.
        try w.print("{t} {d}\n", .{ mode, scores.get(mode) });
    }
    return w.buffered();
}

test "round trip" {
    var scores: Scores = .initFill(0);
    scores.set(.easy, 12);
    scores.set(.hard, 3400);
    var buf: [256]u8 = undefined;
    const text = try format(&buf, scores);
    try std.testing.expectEqualStrings("easy 12\nnormal 0\nhard 3400\n", text);
    try std.testing.expectEqual(scores, parse(text));
}

test "old single-number file counts as normal; junk is ignored" {
    try std.testing.expectEqual(@as(u32, 1670), parse("1670\n").get(.normal));
    const junk = parse("bogus 5\nhard xyz\neasy 7");
    try std.testing.expectEqual(@as(u32, 7), junk.get(.easy));
    try std.testing.expectEqual(@as(u32, 0), junk.get(.hard));
}
