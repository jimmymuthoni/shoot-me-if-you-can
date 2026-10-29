//! Word list, parsed and validated entirely at compile time.
//!
//! `@embedFile` bakes words.txt into the executable as a `*const [N:0]u8`,
//! so there is no file I/O and no allocation at runtime. The path is relative
//! to this source file and must stay inside the module's directory.

const std = @import("std");

pub const min_len = 3;
pub const max_len = 9;

const raw = @embedFile("words.txt");
const separators = " \t\r\n";

/// Number of words in words.txt. A `const` at container (file) level is
/// evaluated at compile time, so this whole block runs inside the compiler.
const word_count = blk: {
    // Comptime code has a budget of backward branches (loop iterations) to
    // catch infinite loops. Parsing a few hundred words needs more than the
    // default 1000.
    @setEvalBranchQuota(100_000);
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, raw, separators);
    while (it.next()) |w| {
        // A bad word becomes a *compile* error, not a runtime crash.
        if (w.len < min_len or w.len > max_len)
            @compileError("word '" ++ w ++ "' must be 3 to 9 letters");
        for (w) |c| if (c < 'a' or c > 'z')
            @compileError("word '" ++ w ++ "' must be lowercase a-z only");
        n += 1;
    }
    if (n == 0) @compileError("words.txt is empty");
    break :blk n;
};

/// All words, sorted by length (shortest first). Each element is a slice
/// pointing into the embedded file, so no text is copied.
const sorted: [word_count][]const u8 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [word_count][]const u8 = undefined;
    var i: usize = 0;
    // Bucket by length: a simple stable sort that is cheap at comptime.
    for (min_len..max_len + 1) |len| {
        var it = std.mem.tokenizeAny(u8, raw, separators);
        while (it.next()) |w| {
            if (w.len == len) {
                out[i] = w;
                i += 1;
            }
        }
    }
    break :blk out;
};

/// `count_up_to[L]` = how many words have length <= L. Because `sorted` is
/// ordered by length, the words of length <= L are `sorted[0..count_up_to[L]]`.
const count_up_to: [max_len + 1]usize = blk: {
    @setEvalBranchQuota(100_000);
    var counts: [max_len + 1]usize = @splat(0);
    for (sorted) |w| {
        for (w.len..max_len + 1) |l| counts[l] += 1;
    }
    break :blk counts;
};

pub fn count() usize {
    return word_count;
}

/// Returns a random word no longer than `longest` letters.
/// `std.Random` is an interface: a pointer plus a function, so any PRNG works.
pub fn random(rng: std.Random, longest: usize) []const u8 {
    const limit = @min(@max(longest, min_len), max_len);
    const n = count_up_to[limit];
    return sorted[rng.uintLessThan(usize, n)];
}

test "word list is loaded and sorted by length" {
    try std.testing.expect(count() >= 200);
    for (sorted[1..], sorted[0 .. sorted.len - 1]) |cur, prev| {
        try std.testing.expect(cur.len >= prev.len);
    }
}

test "random respects the length limit" {
    var prng = std.Random.DefaultPrng.init(42);
    for (0..500) |_| {
        const w = random(prng.random(), 4);
        try std.testing.expect(w.len >= min_len and w.len <= 4);
    }
}
