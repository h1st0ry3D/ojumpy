# Ojumpy

A two-player glyph race for the Omarchy bar. Two racers climb a generated
101-platform tower — the glyphs start as `Ö`, sleep when you leave them alone,
glide, wobble when they walk, shove each other, dodge whatever the mode drops on
them and finish by jumping into the orb at the summit.

Keyboard out of the box; an Xbox/XInput pad is an optional extra. No build step,
no packages, no network: one shell plugin, three small stdlib-only helpers.

**At a glance**

- 101 platforms, generated per round from a seed (same seed ⇒ same course)
- single and double jump, glide while falling, walk wobble, landing ripple
- players are solid: side shoves, riding on the other's head, bump flash
- three ready modes — Race to 100, Asterisk Attack, Glyph Hunt — plus one scaffold
- Asterisk Attack drops bouncing `*` rocks and a bold-`O` power-up; Glyph Hunt
  pairs every drop in both players' colours and scores the catches
- the summit orb ends the round: it breathes, brightens as it pulses, and the
  player who touches it gets the verdict card, confetti and a best time
- `P` pauses (and closing the panel pauses a running round for you)
- synthesised sound cues, theme-aware palette, ghost trail for your falls

## Solo start & split screen

The bar widget shows `ö_Ö` when nothing is running. Open the panel, press `R` to
play solo (`Enter` and pad `Start` do the same from the ready screen): one camera,
one arena.

`J` — or any fresh input from player 2's *pad* (right stick on a single pad, the
second pad, `B`/`X`) — joins the second racer: the board splits into two panes, each
with its own camera, and both glyphs render in both panes. `J` again leaves, back to
solo. A mid-round join spawns P2 clean on the start pad. On the keyboard, `J` (or
the `Splitscreen` button) is the only way in: the arrow keys are P1's own while solo.

## Install (another Omarchy machine)

The plugin folder is self-contained: `Panel.qml` + `manifest.json`, the `ui/` and
`core/` code, the `audio/`, `input/`, `ipc/` and `state/` helpers, the icon and the
committed `audio/sfx/` WAVs. Registration (`plugins[]` + bar layout) and runtime
state do **not** travel.

### Option A: install from a git remote (recommended)

```bash
cd ~/.config/omarchy/plugins/ojumpy
git remote add origin <your-git-url>
git push -u origin main
```

Then on any other Omarchy machine:

```bash
omarchy plugin add <your-git-url> --enable
omarchy plugin enable ojumpy        # if not enabled automatically
```

Updates later: `omarchy plugin update ojumpy`.

### Option B: manual copy

```bash
cp -r ojumpy ~/.config/omarchy/plugins/     # folder name must stay `ojumpy`
omarchy plugin enable ojumpy               # registers in shell.json + bar
omarchy-shell shell rescanPlugins          # or restart the shell
```

`omarchy plugin list` should show `ojumpy` discovered.

## Controller (optional) — Xbox / XInput pads

Keyboard play needs nothing. Gamepads are opt-in: step-by-step pairing, the
one-pad and two-pad mappings and troubleshooting are in **[GAMEPAD.md](GAMEPAD.md)**.
The short version:

1. for an Xbox One/Series pad over Bluetooth, install **Install → Gaming → Xbox
   Controllers** from the Omarchy menu (`xpadneo-dkms`); Xbox 360 and wired Xbox
   One pads need nothing,
2. click the `○ gamepad off` row in the panel (*Ojumpy Manual* section),
3. plug the pad in or pair it.

The plugin asks for no privilege and installs nothing: udev marks joysticks and
logind gives your session access, and the bridge reads exactly the devices udev
classified as joysticks — never keyboards or mice.

## Records and fresh machines

Best times and the chosen mode live in `~/.local/state/ojumpy/game.json`
(created on first run, never inside the plugin folder). Copy that one file to
keep your records on another machine.

- `~/.local/state/ojumpy/` is created 0700 by `state/ojumpy-state.py`; only
  `game.json` is written there.
- The pad bridge keeps its state in memory and streams it to the panel; it has no
  state file. `--log PATH` is available when debugging.
- Controller not detected? See [GAMEPAD.md](GAMEPAD.md), or
  `journalctl --user -t omarchy-shell | grep ojumpy-pad` — the bridge logs which
  event nodes it took.

## Architecture

```
ojumpy/
├── Panel.qml            entry point: plugin state, palette, scale math, the tick
├── manifest.json  preview.png  icon.svg  LICENSE
├── README.md  FILES.md  GAMEPAD.md
├── ui/       the views  ─ GamePanel, BarButton, ReloadMenu, GameBoard,
│                          BoardView, LandRipple, GlyphMetrics, ModeSelect,
│                          Confetti, Plain.js
├── core/     the game   ─ GameEngine, Course.js, GameModes.js
├── audio/    the sound  ─ Sfx.qml, ojumpy-sfx.py, sfx/*.wav
├── input/    ojumpy-pad.py       (evdev bridge, opt-in)
├── ipc/      DebugIpc.qml        (`ojumpy.debug` handlers)
└── state/    ojumpy-state.py, ThemeStore.qml   (state + theme IO)
```

| File | Role |
|---|---|
| `Panel.qml` | The shell entry point: plugin state and helper paths, theme palette roles, scale/fullscreen math, input aggregation, the tick, and the auto-pause. Owns no view ids — `ui/GamePanel.qml` reports its chrome heights back for the sizing math. |
| `core/GameEngine.qml` | The simulation, in fixed base units (440×500): movement, gravity, jump/glide, platforms, players as each other's platforms, hazards, power-ups, the orb, ghosts, cameras, pause, and the mode hooks' dispatch. No view code, no scaling. |
| `core/Course.js` | The course generator as pure functions — `build(config, seed)`, same seed ⇒ same course. |
| `core/GameModes.js` | The rules registry: three ready modes plus a scaffold, each with its tag glyph, hooks and (optionally) a hazard block the engine reads. |
| `ui/GamePanel.qml` | The drop-down card: header (clock, best, fullscreen, close), board slot, action row, the *Ojumpy Manual* accordion and the gamepad switch. |
| `ui/BoardView.qml` | One pane with one camera: platforms, both glyphs, ghosts, the orb, hazards, the power-up, landing ripple, walk wobble, bump glow, pane HUD tag. |
| `ui/GameBoard.qml` | Arena layout (one pane, or two side by side) plus the idle, paused and win overlays. |
| `ui/GlyphMetrics.qml` | The ink geometry of the text art: what keeps glyphs, collision boxes, the ripple and the orb aligned. |
| `ui/LandRipple.qml` | The landing wave: an aligned per-character overlay over the platform's own art. |
| `ui/ModeSelect.qml` | The mode picker overlay. |
| `ui/Confetti.qml` | The win shower. |
| `ui/Plain.js` | Flattening for text the shell renders itself (tooltips). |
| `ui/BarButton.qml` | The bar icon: sizes its slot from the live label, tooltip, click and context menu. |
| `ui/ReloadMenu.qml` | The bar icon's right-click menu (reload the plugin). |
| `ipc/DebugIpc.qml` | The `ojumpy.debug` handlers. |
| `audio/Sfx.qml` | Cue playback: player probe, four-voice pool, one random pitch variant per play. |
| `audio/ojumpy-sfx.py` | The recipe for the committed cues (run by hand, never at startup). |
| `input/ojumpy-pad.py` | The opt-in evdev bridge: joystick-classified devices → one JSON line per update on stdout. |
| `state/ojumpy-state.py` | Descriptor-bound state and theme IO. |
| `state/ThemeStore.qml` | Watches the theme's `colors.toml` and exposes the palette roles. |

`FILES.md` has the per-file detail (invariants, what each helper touches);
everything about pads is in `GAMEPAD.md`.

## Modes

Modes live in `core/GameModes.js`. The engine drives the shared simulation and
delegates the rules to each entry's hooks (`onLand`, `onFall`, `onTick`).

| Mode | Goal | HUD tag | Extras |
|---|---|---|---|
| **Race to 100** | be the first to touch the summit orb | `~` | — |
| **Asterisk Attack** | the same climb, under bombardment | `~` | `*` rocks in three sizes, bouncing off the arena walls, faster as the leader climbs; a bold `O` power-up drops at platform 50 (and every 5 deaths) that absorbs one hit |
| **Glyph Hunt** | catch 10 glyphs of your own colour | `$` | every drop is a matched pair, one per player in their own colour: catch yours for +1 and a bing, touch theirs and it hits like a shove and kills you. No summit orb |
| *Fall Gauntlet* | scaffold, not playable yet | — | — |

The pane HUD tag reads `P1: 3_100 | Ø 4` — owner, the mode's goal glyph in
front of the progress (platform count, or the score in Glyph Hunt), and the death
count once there is one.

## Playing

**Move and jump.** Left/right only — the game is not analog; a stick past ~35 %
counts as a direction. Jump is a fixed velocity and you get two of them: tap again
mid-air for a second full-height jump. *Hold* jump while falling, after at least
one jump, to glide: gravity drops to 35 % and the descent is capped, so a held
press floats you across a gap. The glyph becomes `Ô` (glider) while it lasts.

**The players are `Ö`.** Out of the gate they are `Ö`, and when nobody touches
them they fall asleep: after 3 s they are a small `ö` whose dots blink, then
settle into a closed-eye `o` after ten blinks. Any input wakes them.

**Painted glyphs, not boxes.** Every contact test — standing on a platform, riding
the other player, being hit by a rock — uses the glyph's *painted* span, never the
invisible 20-unit collision box. Sideways the two racers shove each other apart
but stop touching (no box-wide gap); from above you land on the other's head only
when the glyphs line up, no standing on empty diagonal corners, and you are carried
while they walk, jump or glide. A rider is drawn dropped onto the painted head, so
the stack has no gap. Bumping lights both glyphs in a brighter shade of their own
colour for a moment.

**Falls and ghosts.** Dropping off the bottom returns you to the start pad, counts
a death and leaves a muted `Ø` at the spot you left. The trail is a ring of 99
slots per player, newest brightest, drawn on the arena's floor line so it scrolls
with the camera.

**The summit orb.** The last platform carries the orb. It breathes — 18 % larger
and brighter at the peak of a 2 rad/s pulse — and its colour ramps from dark orange
to a fixed pale yellow at 4 rad/s. Round ends on *touch* of the painted body;
standing on the summit does not count. The glyph that touched it is drawn at the
orb's size with a steady glow, and the verdict card waits two seconds so the
arena shows that beat before the confetti starts.

**Pause.** `P`, the `Pause`/`Resume` button, or `Start` on a pad freezes the round:
players, rocks, ghosts and the clock all hold, and resuming shifts the start stamp
so the paused stretch is never charged to the run. Closing the panel pauses a running round
automatically (fullscreen does not — it reopens the panel to relayout), so a round
you cannot see does not keep falling apart. Paused rounds show a `❚❚ paused` card
over the frozen arena. The bar keeps showing the frozen progress while paused —
the label is what sizes the bar icon's slot and the panel is anchored to that
button, so switching it back to `ö_Ö` would shift the whole panel sideways. The
paused state is in the bar tooltip (`Ojumpy — Race to 100 · paused · keyboard`).

**Course generation.** Levels are built in base units from the round seed, on a
discrete grid of climb units (single +1, double +2, bridge ±0) so every hop is one
committed, always-reachable jump. Horizontal spread is a self-avoiding walk with a
heading that bounces off the arena sides, fits each step to the room left and
validates the whole layout; it retries with a fresh seed when it boxes itself in
and falls back to a ladder so a round always has a course. Platform art is drawn
exactly as authored — one pattern per size (`>>><<<`, `=========`,
`<<<<<<>>>>>>`, the start pad, the checkered finish band) — so a platform's
collision width *is* its pattern's width, at 9 base units per character.

## Modes screen

`M` (or the `Mode` button) opens the picker; `1`–`3`, or `↑`/`↓` to move the
highlight and `Enter`, picks a mode; `Esc` closes it without switching. On a pad:
`↑`/`↓` (D-pad or either stick) and `A`. The cursor starts on the mode that is
playing and skips the scaffolded one, so what is highlighted is always something
that can be picked. Picking a mode starts a fresh round.

## Controls

| | Move | Jump | Start |
|---|---|---|---|
| **P1** | `A`/`D` · pad 1 left stick / D-pad | `W` or `Space` · pad `A` | `R` / `Enter` · pad `Start` |
| **P2** | `←`/`→` · pad 2 left stick / D-pad | `↑` or `Enter` (numpad too) · pad `A`/`B`/`X` | `R` / `Enter` (from the ready screen) |

Solo, when P2 has not joined, **both sets drive P1** — WASD + `Space` or arrows +
`Enter`, whichever hand you prefer. `J` (or a fresh pad P2 input) splits them apart
again: then `←`/`→`/`↑`/`Enter` belong to P2 alone.

`J` join/leave P2 · `P` pause · `S` stop · `M` modes (`↑`/`↓` + `Enter` to pick) ·
`F` fullscreen (pad `R3`) · `Esc` close · pad: `Start` start/pause, `Select` modes
(`↑`/`↓` + `A`).

`Enter` and pad `Start` are context-sensitive: while a round runs they jump (P2, or
P1 while solo) and pause; on the ready screen they start a round. After a *win* only
`R` (and the pad's `Select` → `A`) starts a rematch — at the win, `Enter` and `A` are
exactly the buttons everyone is mashing.

Buttons carry the action only; every shortcut lives in the button's tooltip, and
the full list is in the **Ojumpy Manual** accordion at the bottom of the panel
(collapsed by default, remembered in `game.json`). The panel is as tall as its
content and, when needed, as tall as the screen allows; the manual scrolls inside
the room left over rather than pushing the panel past the bottom edge.

## Debug IPC

```bash
omarchy-shell ojumpy.debug state          # live state (players, cameras, hazards, orb)
omarchy-shell ojumpy.debug dims           # scale diagnostics
omarchy-shell ojumpy.debug modes          # mode registry
omarchy-shell ojumpy.debug course         # generated course (idx, x, y, w, kind, glyph)
omarchy-shell ojumpy.debug start 123      # start a round with a fixed seed
omarchy-shell ojumpy.debug mode glyphhunt
omarchy-shell ojumpy.debug join           # player 2 joins (split screen)
omarchy-shell ojumpy.debug leave          # back to solo
omarchy-shell ojumpy.debug pause          # freeze the round
omarchy-shell ojumpy.debug resume         # unfreeze it
omarchy-shell ojumpy.debug fullscreen
omarchy-shell ojumpy open                 # the shell's own panel control
omarchy-shell ojumpy close                # (also: toggle, show, hide)
```

They are a test hook: start/stop/join the local game only — no files, no shell
commands, no persistence beyond the state document. `omarchy-shell ojumpy …` is
not ours: the shell gives every plugin panel an `open`/`close`/`toggle` of its own.

## What it runs, and what it writes

- **`state/ojumpy-state.py`** (stdlib-only, run as `/usr/bin/python3 -I -S -B`)
  reads and writes `~/.local/state/ojumpy/game.json` and reads the active theme's
  `colors.toml`. Directories are walked with held descriptors, reads go through one
  `O_NOFOLLOW|O_NONBLOCK` descriptor that is `fstat`-validated and capped, and writes
  are an exclusive 0600 temporary in the destination directory, fsynced and renamed
  over it. The state directory is forced to 0700 and non-regular entries in it are
  removed, so a planted symlink or FIFO cannot stand in for the state file.
- **`input/ojumpy-pad.py`** (stdlib-only) is the evdev bridge. It is started only
  while the panel's gamepad row is on, opens only devices udev classified as
  joysticks, keeps state in memory and streams JSON lines on stdout. It writes
  nothing unless you pass `--log PATH`.
- **`audio/ojumpy-sfx.py`** is not run by the plugin. It is the offline recipe for
  the committed `audio/sfx/` WAVs — run `python3 -B audio/ojumpy-sfx.py` to
  re-render them after tuning the table at the top (the committed files are
  byte-identical to a fresh run).
- **Sound playback** hands one of those WAVs to the first of `/usr/bin/pw-play`,
  `/usr/bin/paplay`, `/usr/bin/aplay` that exists — absolute paths, one process per
  cue, four recycled voices. `step` while walking, `land` on landing, `jump` on
  every jump, `bump` on shoves (and on rock hits), `bing` for a correct Glyph Hunt
  catch, `orb` when the summit orb is touched.
- Every text item is pinned with `textFormat: Text.PlainText`, and the few strings
  that go into shell-rendered tooltips are flattened and capped first (`ui/Plain.js`).

## Removing

```bash
omarchy plugin remove ojumpy
```

That removes the plugin folder only. What survives, and can be deleted by hand:

| Path | What it is |
|---|---|
| `~/.local/state/ojumpy/game.json` | chosen mode, per-mode best times, manual and gamepad state — **kept**; delete it for a clean slate |
| `~/.local/state/ojumpy/pad.json`, `~/.local/state/ojumpy/sfx/` | leftovers from earlier versions — safe to delete |
| `~/.local/state/ojumpy/pad.log` | only if you enabled `--log` |
| pad driver package | if your Xbox model needed one (Bluetooth / wireless dongle), it came from your package manager |

Nothing else is installed: no services, no timers, no config outside the plugin
folder, no package, no udev rule, no privileged rule, no binary.
