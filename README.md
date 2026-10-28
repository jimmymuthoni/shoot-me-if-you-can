#### shoot-me-if-you-can

A typing game written in Zig with raylib.
Birds fly across the screen carrying words. Type a word to shoot its bird down
before it escapes. Type fast for bonus points, and type cleanly to build up your combo.

#### How to play.

- Each bird carries a word. Start typing it and the cannon locks on to that bird.
- If two birds start with the same letter, the one closest to escaping is chosen.
- Finish the word to shoot the bird down.
- A wrong letter flashes the word red and resets your combo. The lock stays on, so you can keep typing.
- Every bird that reaches the far side of the screen costs you a life. When your lives run out, the game is over.

#### Controls

| Key | Action |
|---|---|
| `a`–`z` | Type the letters of a word |
| `Backspace` / `Esc` | Drop the current target |
| `Enter` | Start, or play again |
| `←` / `→` or `1`–`3` | Choose the difficulty on the menu |
| `Backspace` (on game over) | Back to the menu |
| `Tab` | Music on/off |

`Esc` does not quit the game. Close the window to exit.

#### Scoring

```
word score = word length × 10 × speed bonus × combo
```

- Speed bonus: ×3 if you shoot a bird right as it appears, falling to ×1 as it reaches the far edge.
- Combo:goes up by one for every word typed with no mistakes, up to ×5.
  Any wrong key, or an escaped bird, resets it to ×1.
- Extra life: every 5,000 points (up to 6 lives).

When the game ends you'll see your score, WPM ((correct letters ÷ 5) ÷
minutes), accuracy (correct keys ÷ total keys), how many birds you shot,
and the three letters you missed most.

#### Difficulty

Every 30 seconds the level goes up: birds get faster, appear more often and carry longer words.

| Mode | Lives | Bird speed | Starting word length |
|---|---|---|---|
| Easy | 5 | ×0.75 | up to 4 letters |
| Normal | 3 | ×1.0 | up to 5 letters |
| Hard | 3 | ×1.3 | up to 6 letters |

Each mode keeps its own high score in `highscore.txt`, saved in the folder you run the game from.

#### Golden birds

About 1 in 12 birds is golden and carries a power-up. Shoot it to trigger:

- FREEZE: every bird slows to a quarter of its speed for 4 seconds.
- BOMB: every bird on screen is shot down.
- +1 LIFE: you get an extra life.

### Building

You need **Zig 0.17.0**. raylib is downloaded and compiled automatically; you don't need to install it separately.

On Debian/Ubuntu Linux, raylib also needs these X11 development packages:

```sh
sudo apt install libx11-dev libgl-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev
```

Then:

```sh
zig build run      # build and play
zig build          # build only; the game is in zig-out/bin/bird_typer
zig build test     # run the unit tests (no window needed)
```

You can also cross-compile for Windows, for example
`zig build -Dtarget=x86_64-windows`.

### Custom art and sound

The game works with no extra files: birds are drawn from simple shapes, and
the sound effects and music are generated in code. To use your own, create an
`assets/` folder next to where you run the game and add any of these:

| File | Used for |
|---|---|
| `assets/bird.png` | The bird. Facing right, either a single image or a horizontal strip of square animation frames (e.g. 4 frames of 64×64 = 256×64). |
| `assets/shoot.wav` | Each correct letter |
| `assets/hit.wav` | A bird being shot. Plays higher as your combo grows. |
| `assets/miss.wav` | A wrong key or an escaped bird |
| `assets/powerup.wav` | A power-up or an extra life |
| `assets/game_over.wav` | The game ending |
| `assets/music.ogg` (or `.mp3` / `.wav`) | Background music, looped |

Missing or broken files are skipped, and the built-in version is used instead.

#### Project layout

```
build.zig          build script: the run and test commands, and the raylib dependency
build.zig.zon      package manifest (pins the exact raylib-zig version)
src/
  main.zig         entry point: window, frame loop, keyboard input
  game.zig         all game rules and state, plus most of the tests
  render.zig       all drawing: birds, effects, HUD, menu, game-over screen
  words.zig        loads words.txt into the program at compile time
  words.txt        the word list (301 lowercase words, 3–9 letters)
  assets.zig       loads optional art and sounds from assets/
  synth.zig        generates the built-in sound effects and music
  highscore.zig    reads and writes highscore.txt
```

#### How it fits together

Every frame, `main.zig` reads the keyboard into a plain `Input` struct and
passes it to `game.zig`, which updates the game. `game.zig` returns the
sounds it wants played, and `render.zig` then draws the result.

`game.zig` doesn't use raylib at all, so the game rules can be tested without
opening a window. All birds, feathers and popups live in fixed-size arrays,
so the game never allocates memory while it runs.

### Changing things

- Tuning: the constants at the top of `src/game.zig` (spawn rates,
  power-up chance, freeze length, extra-life threshold) and `Mode.params()`
  for the difficulty modes.
- Words: add lines to `src/words.txt`. Words must be lowercase a–z and 3–9
  letters long; anything else fails the build with a message naming the word.
- New power-up or sound: add a value to the `Power` or `SoundId` enum. The
  compiler then points to every `switch` that needs a case for it.
