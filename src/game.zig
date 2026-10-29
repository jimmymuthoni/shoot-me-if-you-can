
const std = @import("std");
const words = @import("words.zig");

pub const screen_w: f32 = 800;
pub const screen_h: f32 = 600;

pub const max_birds = 16;
pub const max_particles = 256;
pub const max_popups = 16;
pub const max_lives = 6;
pub const max_combo = 5;

/// Difficulty goes up one level every this many seconds.
pub const level_seconds: f32 = 30;
/// Birds spawn (and escape) this far beyond the screen edge.
pub const spawn_margin: f32 = 50;
/// How long a wrong-key red flash and the shot line stay visible.
pub const flash_time: f32 = 0.25;
pub const shot_time: f32 = 0.15;
pub const popup_time: f32 = 1.0;

/// Power-ups.
pub const power_chance: f32 = 0.08;
pub const freeze_time: f32 = 4;
/// While frozen, birds (and spawning) run at this fraction of normal speed.
pub const freeze_factor: f32 = 0.25;
pub const extra_life_every: u32 = 5000;

const gravity: f32 = 600;
const feather_gravity: f32 = 120;

/// Where shots come from: a little cannon at the bottom centre.
pub const turret: Vec2 = .{ .x = screen_w / 2, .y = screen_h - 28 };


//tiny vector so this file stays raylib-free. render.zig converts.
pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const GameState = enum { menu, playing, game_over };

//Difficulty mode, chosen on the menu. 
pub const Mode = enum {
    easy,
    normal,
    hard,

    pub const Params = struct {
        lives: u8,
        speed_mult: f32,
        spawn_mult: f32,
        speed_cap: f32,
        /// Longest word at level 1; grows by one each level.
        base_word_len: usize,
    };

    pub fn params(self: Mode) Params {
        return switch (self) {
            .easy => .{ .lives = 5, .speed_mult = 0.75, .spawn_mult = 1.3, .speed_cap = 200, .base_word_len = 4 },
            .normal => .{ .lives = 3, .speed_mult = 1.0, .spawn_mult = 1.0, .speed_cap = 260, .base_word_len = 5 },
            .hard => .{ .lives = 3, .speed_mult = 1.3, .spawn_mult = 0.75, .speed_cap = 330, .base_word_len = 6 },
        };
    }

    pub fn name(self: Mode) [:0]const u8 {
        return switch (self) {
            .easy => "Easy",
            .normal => "Normal",
            .hard => "Hard",
        };
    }

    /// Cycle through the modes. `std.meta.tags` is the array of all values.
    pub fn step(self: Mode, delta: i32) Mode {
        const all = std.meta.tags(Mode);
        const n: i32 = @intCast(all.len);
        const i = @mod(@as(i32, @intFromEnum(self)) + delta, n);
        return all[@intCast(i)];
    }
};

/// Sounds the game wants played this frame. main.zig maps them to audio.
pub const SoundId = enum { shoot, hit, miss, game_over, powerup };

/// Golden birds carry one of these.
pub const Power = enum {
    freeze,
    bomb,
    life,

    pub fn name(self: Power) [:0]const u8 {
        return switch (self) {
            .freeze => "FREEZE",
            .bomb => "BOMB",
            .life => "+1 LIFE",
        };
    }
};

/// Everything the game needs to know about the keyboard for one frame.
pub const Input = struct {
    /// `undefined` = "don't care about initial contents"; `char_count`
    /// says how much of the buffer is valid.
    chars: [16]u8 = undefined,
    char_count: usize = 0,
    enter: bool = false,
    /// Backspace or Escape: drop the current target (or leave game over).
    unlock: bool = false,
    left: bool = false,
    right: bool = false,

    pub fn pushChar(self: *Input, c: u8) void {
        if (self.char_count < self.chars.len) {
            self.chars[self.char_count] = c;
            self.char_count += 1;
        }
    }

    pub fn typed(self: *const Input) []const u8 {
        return self.chars[0..self.char_count];
    }
};

pub const BirdPhase = enum { flying, falling };

pub const Bird = struct {
    word: []const u8,
    pos: Vec2,
    /// Only used while falling.
    vel: Vec2 = .{},
    /// +1 = flying right, -1 = flying left.
    dir: f32,
    speed: f32,
    start_x: f32,
    base_y: f32,
    /// Golden bird power, or null for a normal bird.
    power: ?Power = null,
    /// How many letters of `word` have been typed correctly.
    typed: usize = 0,
    /// Seconds left of the red "wrong key" flash.
    flash: f32 = 0,
    phase: BirdPhase = .flying,
    /// Rotation in degrees (the tumble when shot).
    angle: f32 = 0,
    spin: f32 = 0,
    /// Seconds alive; drives the wing flap and bobbing.
    age: f32 = 0,

    /// 0.0 = just spawned, 1.0 = about to escape.
    pub fn progress(self: Bird) f32 {
        const total = screen_w + 2 * spawn_margin;
        return std.math.clamp(@abs(self.pos.x - self.start_x) / total, 0, 1);
    }

    fn escaped(self: Bird) bool {
        return if (self.dir > 0)
            self.pos.x > screen_w + spawn_margin
        else
            self.pos.x < -spawn_margin;
    }
};

pub const Particle = struct {
    pos: Vec2,
    vel: Vec2,
    angle: f32,
    spin: f32,
    life: f32,
    max_life: f32,
};

pub const Shot = struct {
    from: Vec2,
    to: Vec2,
    timer: f32,
};

/// Floating text. A tagged union: exactly one field is active, and `switch`
/// on it tells you which (and gives you its payload).
pub const PopupText = union(enum) {
    points: u32,
    power: Power,
    extra_life, // a field with no payload (type `void`)
};

pub const Popup = struct {
    pos: Vec2,
    text: PopupText,
    life: f32,
};

pub const Stats = struct {
    score: u32 = 0,
    /// Every key that matched the expected letter.
    correct_keys: u32 = 0,
    /// Every letter key pressed while playing.
    total_keys: u32 = 0,
    /// Letters of fully completed words (used for WPM).
    correct_chars: u32 = 0,
    words_killed: u32 = 0,
    /// Words completed in a row without a mistake.
    streak: u32 = 0,
    /// Seconds spent in the playing state.
    elapsed: f32 = 0,
    /// missed['e' - 'a'] = how often you were supposed to type 'e' but didn't.
    missed: [26]u32 = @splat(0),

    pub fn combo(self: Stats) u32 {
        return @min(1 + self.streak, max_combo);
    }

    pub fn wpm(self: Stats) f32 {
        return calcWpm(self.correct_chars, self.elapsed);
    }

    pub fn accuracy(self: Stats) f32 {
        return calcAccuracy(self.correct_keys, self.total_keys);
    }

    /// Fills `out` with the most-missed letters, worst first, and returns
    /// the used part. Letters never missed are left out.
    pub fn mostMissed(self: *const Stats, out: []u8) []u8 {
        var taken: [26]bool = @splat(false);
        var n: usize = 0;
        while (n < out.len) : (n += 1) {
            var best: ?usize = null;
            for (self.missed, 0..) |count, i| {
                if (taken[i] or count == 0) continue;
                if (best == null or count > self.missed[best.?]) best = i;
            }
            const i = best orelse break;
            taken[i] = true;
            out[n] = 'a' + @as(u8, @intCast(i));
        }
        return out[0..n];
    }
};

// ------------------------------------------------------- pure formulas --

/// WPM = (correct_chars / 5) / minutes. A "word" is 5 characters by convention.
pub fn calcWpm(correct_chars: u32, seconds: f32) f32 {
    // Avoid a silly spike (or division by zero) in the first second.
    if (seconds < 1) return 0;
    const chars: f32 = @floatFromInt(correct_chars);
    return (chars / 5) / (seconds / 60);
}

/// Percentage 0..100. No keys pressed yet counts as perfect.
pub fn calcAccuracy(correct_keys: u32, total_keys: u32) f32 {
    if (total_keys == 0) return 100;
    const c: f32 = @floatFromInt(correct_keys);
    const t: f32 = @floatFromInt(total_keys);
    return 100 * c / t;
}

/// x3 when shot right at the edge it entered from, falling to x1 at the far edge.
pub fn speedBonus(progress: f32) f32 {
    return 1 + 2 * (1 - std.math.clamp(progress, 0, 1));
}

/// word_length * 10 * speed_bonus * combo, rounded to a whole number.
pub fn wordScore(word_len: usize, progress: f32, combo: u32) u32 {
    const base: f32 = @floatFromInt(word_len * 10);
    const mult: f32 = @floatFromInt(combo);
    return @intFromFloat(@round(base * speedBonus(progress) * mult));
}

// ------------------------------------------------------------------ Game --

pub const Game = struct {
    state: GameState = .menu,
    mode: Mode = .normal,

    // Fixed-size pools: an empty slot is `null`. No allocator anywhere.
    // `@splat(null)` fills every element of the array with `null`.
    birds: [max_birds]?Bird = @splat(null),
    particles: [max_particles]?Particle = @splat(null),
    popups: [max_popups]?Popup = @splat(null),
    shot: ?Shot = null,

    /// Index into `birds` of the locked-on bird, or null if none.
    target: ?usize = null,
    lives: u8 = 3,
    stats: Stats = .{},
    spawn_timer: f32 = 0,
    next_life_score: u32 = extra_life_every,

    /// Seconds of slow motion left (freeze power-up).
    freeze_timer: f32 = 0,
    /// White screen flash after a bomb, in seconds.
    screen_flash: f32 = 0,
    /// Total seconds since launch, in every state. Drives background scrolling.
    clock: f32 = 0,
    /// Combo multiplier of the last kill, so the hit sound can rise in pitch.
    hit_combo: u32 = 1,

    /// Best score per mode. EnumArray = fixed array indexed by an enum.
    high_scores: std.EnumArray(Mode, u32) = .initFill(0),
    new_record: bool = false,

    rng: std.Random.DefaultPrng,
    /// Sounds requested during the last `update`. `.empty` is a declaration
    /// on the EnumSet type; Zig infers the type from the field, hence the dot.
    sounds: std.EnumSet(SoundId) = .empty,

    pub fn init(seed: u64, high_scores: std.EnumArray(Mode, u32)) Game {
        return .{ .rng = .init(seed), .high_scores = high_scores };
    }

    /// Start a fresh round, keeping the RNG, mode, clock and high scores.
    pub fn reset(self: *Game) void {
        self.* = .{
            .state = .playing,
            .mode = self.mode,
            .lives = self.mode.params().lives,
            .rng = self.rng,
            .clock = self.clock,
            .high_scores = self.high_scores,
            .spawn_timer = 0.5, // first bird shows up quickly
        };
    }

    pub fn highScore(self: *const Game) u32 {
        return self.high_scores.get(self.mode);
    }

    // --- difficulty, derived from mode and elapsed time ---

    pub fn level(self: *const Game) u32 {
        return @intFromFloat(@floor(self.stats.elapsed / level_seconds));
    }

    fn levelF(self: *const Game) f32 {
        return @floatFromInt(self.level());
    }

    pub fn birdSpeed(self: *const Game) f32 {
        const p = self.mode.params();
        return @min((70 + 18 * self.levelF()) * p.speed_mult, p.speed_cap);
    }

    pub fn spawnInterval(self: *const Game) f32 {
        return @max(0.6, (2.6 - 0.3 * self.levelF()) * self.mode.params().spawn_mult);
    }

    pub fn maxWordLen(self: *const Game) usize {
        return @min(words.max_len, self.mode.params().base_word_len + self.level());
    }

    // --- per-frame update ---

    pub fn update(self: *Game, dt: f32, input: Input) void {
        self.sounds = .empty;
        self.clock += dt;
        switch (self.state) {
            .menu => self.updateMenu(input),
            .playing => self.updatePlaying(dt, input),
            .game_over => {
                if (input.enter) self.reset() else if (input.unlock) self.state = .menu;
            },
        }
        // Falling birds, feathers, popups and the shot animate in every state.
        self.updateFalling(dt);
        self.updateEffects(dt);
    }

    fn updateMenu(self: *Game, input: Input) void {
        if (input.left) self.mode = self.mode.step(-1);
        if (input.right) self.mode = self.mode.step(1);
        // Number keys pick a mode directly: '1' = first mode, ...
        for (input.typed()) |c| {
            const tags = std.meta.tags(Mode);
            if (c >= '1' and c < '1' + tags.len) self.mode = tags[c - '1'];
        }
        if (input.enter) self.reset();
    }

    fn updatePlaying(self: *Game, dt: f32, input: Input) void {
        self.stats.elapsed += dt;
        self.freeze_timer = @max(0, self.freeze_timer - dt);
        // "World time" runs slower while frozen; the player's clock does not.
        const world_dt = if (self.freeze_timer > 0) dt * freeze_factor else dt;

        if (input.unlock) self.unlock();
        for (input.typed()) |c| {
            self.handleChar(c);
            if (self.state != .playing) return;
        }

        self.updateFlying(world_dt, dt);
        if (self.state != .playing) return;

        self.spawn_timer -= world_dt;
        if (self.spawn_timer <= 0) {
            self.spawnBird();
            self.spawn_timer += self.spawnInterval();
        }
    }

    fn unlock(self: *Game) void {
        if (self.target) |i| {
            if (self.birds[i]) |*b| b.typed = 0;
        }
        self.target = null;
    }

    fn handleChar(self: *Game, key: u8) void {
        const c = std.ascii.toLower(key);
        if (c < 'a' or c > 'z') return; // ignore spaces, digits, punctuation

        self.stats.total_keys += 1;

        // `orelse` unwraps an optional or evaluates the right side.
        // Chained: use the current target, else search for one, else it's a miss.
        const idx = self.target orelse self.findTarget(c) orelse {
            self.mistake(null);
            return;
        };

        // `.?` asserts the optional is non-null; `&` takes a pointer to the
        // payload so we modify the bird in the array, not a copy.
        const bird = &self.birds[idx].?;
        if (bird.word[bird.typed] == c) {
            self.target = idx;
            bird.typed += 1;
            self.stats.correct_keys += 1;
            self.sounds.insert(.shoot);
            if (bird.typed == bird.word.len) self.kill(idx);
        } else {
            self.mistake(bird);
        }
    }

    /// The flying bird whose word starts with `c` and is closest to escaping.
    fn findTarget(self: *const Game, c: u8) ?usize {
        var best: ?usize = null;
        var best_progress: f32 = -1;
        for (self.birds, 0..) |slot, i| {
            const b = slot orelse continue;
            if (b.phase != .flying or b.word[0] != c) continue;
            const p = b.progress();
            if (p > best_progress) {
                best = i;
                best_progress = p;
            }
        }
        return best;
    }

    /// `?*Bird`: an optional pointer. A wrong key with no target has no bird
    /// to flash, and no "expected" letter to blame in the miss stats.
    fn mistake(self: *Game, bird: ?*Bird) void {
        if (bird) |b| {
            b.flash = flash_time;
            self.stats.missed[b.word[b.typed] - 'a'] += 1;
        }
        self.stats.streak = 0;
        self.sounds.insert(.miss);
    }

    fn kill(self: *Game, idx: usize) void {
        const b = &self.birds[idx].?;
        const s = &self.stats;

        self.hit_combo = s.combo();
        self.addScore(wordScore(b.word.len, b.progress(), s.combo()), b.pos);
        s.correct_chars += @intCast(b.word.len);
        s.words_killed += 1;
        s.streak += 1;

        self.shot = .{ .from = turret, .to = b.pos, .timer = shot_time };
        self.knockDown(b);
        self.target = null;
        self.sounds.insert(.hit);

        if (b.power) |p| self.activatePower(p, b.pos);
    }

    /// Switch a bird to its falling tumble and burst out some feathers.
    fn knockDown(self: *Game, b: *Bird) void {
        const r = self.rng.random();
        b.phase = .falling;
        b.vel = .{ .x = b.dir * b.speed * 0.4, .y = -160 };
        b.spin = (if (r.boolean()) @as(f32, 1) else -1) * (360 + 360 * r.float(f32));
        self.spawnFeathers(b.pos, 16);
    }

    fn addScore(self: *Game, points: u32, at: Vec2) void {
        self.stats.score += points;
        self.spawnPopup(at, .{ .points = points });

        while (self.stats.score >= self.next_life_score) {
            self.next_life_score += extra_life_every;
            if (self.lives < max_lives) {
                self.lives += 1;
                self.spawnPopup(.{ .x = turret.x, .y = turret.y - 50 }, .extra_life);
                self.sounds.insert(.powerup);
            }
        }
    }

    fn activatePower(self: *Game, power: Power, at: Vec2) void {
        switch (power) {
            .freeze => self.freeze_timer = freeze_time,
            .life => self.lives = @min(self.lives + 1, max_lives),
            .bomb => {
                self.screen_flash = 0.3;
                for (&self.birds) |*slot| {
                    const b = if (slot.*) |*b| b else continue;
                    if (b.phase != .flying) continue;
                    // Bombed birds score their base value, no bonuses.
                    self.addScore(@intCast(b.word.len * 10), b.pos);
                    self.knockDown(b);
                }
                self.target = null;
            },
        }
        self.spawnPopup(.{ .x = at.x, .y = at.y - 30 }, .{ .power = power });
        self.sounds.insert(.powerup);
    }

    fn loseLife(self: *Game) void {
        self.lives -|= 1; // saturating subtract: never wraps below 0
        self.stats.streak = 0;
        self.sounds.insert(.miss);
        if (self.lives == 0) self.gameOver();
    }

    fn gameOver(self: *Game) void {
        self.state = .game_over;
        self.target = null;
        self.freeze_timer = 0;
        if (self.stats.score > self.highScore()) {
            self.high_scores.set(self.mode, self.stats.score);
            self.new_record = true;
        }
        self.sounds.insert(.game_over);
    }

    /// `dt` is slowed by freeze; `real_dt` is used for UI timers like the red flash.
    fn updateFlying(self: *Game, dt: f32, real_dt: f32) void {
        // Iterate by pointer (`&self.birds`, `|*slot|`) so we can clear slots.
        for (&self.birds, 0..) |*slot, i| {
            // `|*b|` captures a pointer to the payload inside the optional.
            const b = if (slot.*) |*b| b else continue;
            if (b.phase != .flying) continue;
            b.age += dt;
            b.flash = @max(0, b.flash - real_dt);
            b.pos.x += b.dir * b.speed * dt;
            b.pos.y = b.base_y + @sin(b.age * 3) * 10;
            if (b.escaped()) {
                slot.* = null;
                if (self.target == i) self.target = null;
                self.loseLife();
                if (self.state != .playing) return;
            }
        }
    }

    fn updateFalling(self: *Game, dt: f32) void {
        for (&self.birds) |*slot| {
            const b = if (slot.*) |*b| b else continue;
            if (b.phase != .falling) continue;
            b.vel.y += gravity * dt;
            b.pos.x += b.vel.x * dt;
            b.pos.y += b.vel.y * dt;
            b.angle += b.spin * dt;
            if (b.pos.y > screen_h + 60) slot.* = null;
        }
    }

    fn updateEffects(self: *Game, dt: f32) void {
        for (&self.particles) |*slot| {
            const p = if (slot.*) |*p| p else continue;
            p.life -= dt;
            if (p.life <= 0) {
                slot.* = null;
                continue;
            }
            p.vel.y += feather_gravity * dt;
            p.vel.x *= 1 - 1.5 * dt; // air drag
            p.pos.x += p.vel.x * dt;
            p.pos.y += p.vel.y * dt;
            p.angle += p.spin * dt;
        }

        for (&self.popups) |*slot| {
            const p = if (slot.*) |*p| p else continue;
            p.life -= dt;
            p.pos.y -= 40 * dt; // drift upwards
            if (p.life <= 0) slot.* = null;
        }

        if (self.shot) |*s| {
            s.timer -= dt;
            if (s.timer <= 0) self.shot = null;
        }
        self.screen_flash = @max(0, self.screen_flash - dt);
    }

    fn spawnBird(self: *Game) void {
        // `for ... else`: the else branch runs if the loop never hit `break`.
        const slot = for (self.birds, 0..) |b, i| {
            if (b == null) break i;
        } else return; // every slot busy: skip this spawn

        const r = self.rng.random();
        const from_left = r.boolean();
        const start_x = if (from_left) -spawn_margin else screen_w + spawn_margin;
        const y = 80 + r.float(f32) * (screen_h - 280);

        self.birds[slot] = .{
            .word = self.pickWord(),
            .pos = .{ .x = start_x, .y = y },
            .dir = if (from_left) 1 else -1,
            .speed = self.birdSpeed() * (0.85 + 0.3 * r.float(f32)),
            .start_x = start_x,
            .base_y = y,
            .power = self.rollPower(),
            .age = r.float(f32) * 10, // so wings don't flap in sync
        };
    }

    /// Occasionally make a golden bird; never two at once.
    fn rollPower(self: *Game) ?Power {
        const r = self.rng.random();
        if (r.float(f32) >= power_chance) return null;
        for (self.birds) |slot| {
            const b = slot orelse continue;
            if (b.phase == .flying and b.power != null) return null;
        }
        // `r.enumValue` picks a random tag of the enum.
        const p = r.enumValue(Power);
        return if (p == .life and self.lives >= max_lives) .freeze else p;
    }

    /// Prefer a word whose first letter isn't already on screen, so the
    /// first keypress is never ambiguous. Gives up after a few tries.
    fn pickWord(self: *Game) []const u8 {
        const r = self.rng.random();
        var word = words.random(r, self.maxWordLen());
        for (0..12) |_| {
            if (!self.firstLetterInUse(word[0])) break;
            word = words.random(r, self.maxWordLen());
        }
        return word;
    }

    fn firstLetterInUse(self: *const Game, c: u8) bool {
        for (self.birds) |slot| {
            const b = slot orelse continue;
            if (b.phase == .flying and b.word[0] == c) return true;
        }
        return false;
    }

    fn spawnPopup(self: *Game, at: Vec2, text: PopupText) void {
        for (&self.popups) |*slot| {
            if (slot.* == null) {
                slot.* = .{ .pos = at, .text = text, .life = popup_time };
                return;
            }
        }
    }

    fn spawnFeathers(self: *Game, at: Vec2, n: usize) void {
        const r = self.rng.random();
        var left = n;
        for (&self.particles) |*slot| {
            if (left == 0) break;
            if (slot.* != null) continue;
            const angle = r.float(f32) * std.math.tau;
            const speed = 60 + r.float(f32) * 140;
            const life = 0.8 + r.float(f32) * 0.8;
            slot.* = .{
                .pos = at,
                .vel = .{ .x = @cos(angle) * speed, .y = @sin(angle) * speed - 60 },
                .angle = r.float(f32) * 360,
                .spin = (r.float(f32) - 0.5) * 720,
                .life = life,
                .max_life = life,
            };
            left -= 1;
        }
    }
};

// ----------------------------------------------------------------- tests --
// Run with: zig test src/game.zig   (or `zig build test` for everything)

const testing = std.testing;

test "wpm: 250 correct chars in one minute is 50 wpm" {
    try testing.expectApproxEqAbs(@as(f32, 50), calcWpm(250, 60), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 100), calcWpm(250, 30), 0.001);
    try testing.expectEqual(@as(f32, 0), calcWpm(10, 0.5));
}

test "accuracy" {
    try testing.expectApproxEqAbs(@as(f32, 90), calcAccuracy(45, 50), 0.001);
    try testing.expectEqual(@as(f32, 100), calcAccuracy(0, 0));
    try testing.expectEqual(@as(f32, 0), calcAccuracy(0, 7));
}

test "word score: early kills and combos pay more" {
    try testing.expectEqual(@as(u32, 150), wordScore(5, 0, 1)); // 50 * 3 * 1
    try testing.expectEqual(@as(u32, 100), wordScore(5, 1, 2)); // 50 * 1 * 2
    try testing.expectEqual(@as(u32, 100), wordScore(5, 0.5, 1)); // 50 * 2 * 1
}

/// Test helper: a game in the playing state with no random spawns.
fn testGame(mode: Mode) Game {
    var g = Game.init(1, .initFill(0));
    g.mode = mode;
    g.reset();
    g.spawn_timer = 999;
    return g;
}

/// Test helper: put a bird with a known word into a slot.
fn placeBird(g: *Game, slot: usize, word: []const u8, x: f32) void {
    g.birds[slot] = .{
        .word = word,
        .pos = .{ .x = x, .y = 200 },
        .dir = 1,
        .speed = 50,
        .start_x = -spawn_margin,
        .base_y = 200,
    };
}

fn typeText(g: *Game, text: []const u8) void {
    var input: Input = .{};
    for (text) |c| input.pushChar(c);
    g.update(0.0, input);
}

test "typing locks on, wrong key keeps the lock, finishing kills" {
    var g = testGame(.normal);
    placeBird(&g, 0, "cat", 100);

    typeText(&g, "c");
    try testing.expectEqual(@as(?usize, 0), g.target);

    typeText(&g, "x"); // wrong: flashes, target stays locked
    try testing.expectEqual(@as(?usize, 0), g.target);
    try testing.expect(g.birds[0].?.flash > 0);
    try testing.expectEqual(@as(u32, 1), g.stats.missed['a' - 'a']); // expected 'a'

    typeText(&g, "at");
    try testing.expectEqual(@as(?usize, null), g.target);
    try testing.expectEqual(BirdPhase.falling, g.birds[0].?.phase);
    try testing.expect(g.stats.score > 0);
    try testing.expectApproxEqAbs(@as(f32, 75), g.stats.accuracy(), 0.001);
}

test "first letter targets the bird closest to escaping" {
    var g = testGame(.normal);
    placeBird(&g, 0, "dog", 100);
    placeBird(&g, 1, "duck", 600); // further along its path

    typeText(&g, "d");
    try testing.expectEqual(@as(?usize, 1), g.target);
}

test "combo grows with clean words and resets on a mistake" {
    var g = testGame(.normal);
    placeBird(&g, 0, "cat", 100);
    placeBird(&g, 1, "dog", 100);

    typeText(&g, "catdog");
    try testing.expectEqual(@as(u32, 3), g.stats.combo());
    typeText(&g, "q"); // no bird starts with q
    try testing.expectEqual(@as(u32, 1), g.stats.combo());
}

test "escaped birds cost lives and end the game" {
    var g = testGame(.normal);
    for (0..3) |i| placeBird(&g, i, "owl", screen_w + spawn_margin + 1);
    g.update(0.01, .{});
    try testing.expectEqual(GameState.game_over, g.state);
    try testing.expectEqual(@as(u8, 0), g.lives);
    try testing.expectEqual(@as(u32, 0), g.highScore());
}

test "modes set starting lives" {
    try testing.expectEqual(@as(u8, 5), testGame(.easy).lives);
    try testing.expectEqual(@as(u8, 3), testGame(.hard).lives);
    try testing.expectEqual(Mode.easy, Mode.normal.step(-1));
    try testing.expectEqual(Mode.easy, Mode.hard.step(1)); // wraps around
}

test "crossing 5000 points grants an extra life" {
    var g = testGame(.normal);
    g.stats.score = extra_life_every - 10;
    placeBird(&g, 0, "cat", 100);
    typeText(&g, "cat");
    try testing.expectEqual(@as(u8, 4), g.lives);
    try testing.expectEqual(2 * extra_life_every, g.next_life_score);
}

test "bomb bird knocks down every bird on screen" {
    var g = testGame(.normal);
    placeBird(&g, 0, "cat", 100);
    g.birds[0].?.power = .bomb;
    placeBird(&g, 1, "dog", 300);
    placeBird(&g, 2, "owl", 500);

    typeText(&g, "cat");
    for (g.birds[0..3]) |b| try testing.expectEqual(BirdPhase.falling, b.?.phase);
}

test "freeze bird slows the others down" {
    var g = testGame(.normal);
    placeBird(&g, 0, "ice", 100);
    g.birds[0].?.power = .freeze;
    placeBird(&g, 1, "dog", 100);

    typeText(&g, "ice");
    g.update(1.0, .{});
    // speed 50 * freeze_factor 0.25 * 1 second = 12.5 pixels
    try testing.expectApproxEqAbs(@as(f32, 112.5), g.birds[1].?.pos.x, 0.01);
}

test "most missed letters, worst first" {
    var s: Stats = .{};
    s.missed['e' - 'a'] = 4;
    s.missed['t' - 'a'] = 2;
    s.missed['q' - 'a'] = 7;
    var buf: [5]u8 = undefined;
    try testing.expectEqualStrings("qet", s.mostMissed(&buf));
}

test {
    // Also run the tests in words.zig when testing this file.
    _ = words;
}
