# Ojumpy — file map

Everything needed to build or modify the game lives in this folder and can be
committed as-is. Runtime artifacts live OUTSIDE it (see below): the Omarchy shell
hot-reloads this directory on any file change, so anything written frequently
would trigger a reload loop.

## Structure

```
ojumpy/
├── Panel.qml            entry point (manifest entryPoints: barWidget + panel)
├── manifest.json        schemaVersion 1, id `ojumpy`
├── preview.png  icon.svg  LICENSE
├── README.md  FILES.md  GAMEPAD.md
├── ui/                  the views: GamePanel (the drop-down card), BarButton,
│                        ReloadMenu, GameBoard, BoardView, LandRipple,
│                        GlyphMetrics, ModeSelect, Confetti, Plain.js
├── core/                simulation and pure logic: GameEngine, Course.js,
│                        GameModes.js
├── audio/               Sfx.qml, ojumpy-sfx.py (the recipe), sfx/*.wav (committed)
├── input/               ojumpy-pad.py (evdev bridge, opt-in)
├── ipc/                 DebugIpc.qml (`ojumpy.debug` handlers)
└── state/               ojumpy-state.py (state + theme IO), ThemeStore.qml
```

QML resolves each folder as a module: `Panel.qml` (the only file at the root)
imports `"ui"`, `"core"`, `"audio"`, `"state"` and `"ipc"`, and components inside a
folder see their siblings directly. Helpers are addressed relative to the file that
spawns them (`input/ojumpy-pad.py`, `state/ojumpy-state.py`) or to themselves
(`audio/Sfx.qml` reads `sfx/`).

## File map

| File | Role |
|---|---|
| `Panel.qml` | The shell entry point. Owns plugin state and helper paths, the theme palette roles, the scale/fullscreen math, the input aggregation (keyboard + pad), the 16 ms tick, the auto-pause when the panel is closed, and the bar label (`N_target` progress, the score in collect modes, `ö_Ö` when idle/paused). It instantiates the components below and owns no view ids: `ui/GamePanel.qml` reports its chrome heights (`hdrRowH`, `btnRowH`, `helpSectionH`, `helpToggleH`, `padToggleH`, `boardSlotH`) for `_chromeH`/`_helpBudget`. Pad input arrives on the bridge's stdout — capped per line, every field re-coerced in `applyPadLine`. The tick also turns the pad's `up`/`down`/`confirm` into mode-picker edges (rising edge only, flags kept hot while the picker is closed so a held button cannot act on open). |
| `manifest.json` | Plugin manifest: kind `bar-widget` + `panel`, both entry points `Panel.qml`. |
| `core/GameEngine.qml` | The simulation in fixed base units (440×500, constant physics) — no view code, no scaling. Runs players (move, jump, double jump, glide, landings, falls), platforms as collision boxes, player-on-player contact (painted-glyph width: side shoves, head riding, carry), the camera pair, the mode hooks, the hazard pool, the power-ups, the finish orb, the ghost ring and the pause. Views only read it and call `startRound`/`stopGame`/`tick`/`pauseGame`/`resumeGame`/`joinP2`/`leaveP2`. |
| `core/Course.js` | The course generator as pure functions: `build(config, seed)` depends on nothing but the tuning config and the round seed. Discrete climb-unit steps, weighted step kinds, the three-size pool, the self-avoiding walk with its validation, and the ladder fallback. |
| `core/GameModes.js` | The rules registry. A mode is `{ id, name, tagline, tagGlyph, ready, tracksBest, orb?, hooks, hazard? }`; the engine delegates `onLand`/`onFall`/`onTick` and reads `hazard` verbatim (glyph(s), sizes, gap/angle range, fall speed ramp, teams, target, power-up platform). Three ready modes (race, asterisks, glyphhunt) plus a scaffold. `find()` is the validator (an unknown id must not be probed through `get()`, which falls back to race). |
| `ui/GamePanel.qml` | The drop-down card (`KeyboardPanel`): header (mode + clock/best, fullscreen, close), board slot (`GameBoard` + `ModeSelect`), action row (Start/Stop, Mode, Solo/Splitscreen, Restart, Pause/Resume), the *Ojumpy Manual* accordion, the gamepad switch and the win confetti. Its `gameFocus` item owns the keyboard: one `Keys.onPressed` that marks `keysDown` for the game and routes the picker's `↑`/`↓`/`Enter` to `modeMoveCursor`/`modeActivateCursor` (the same two functions the pad tick calls). View-only. |
| `ui/GameBoard.qml` | Arena layout: one `BoardView` solo, two side by side with a divider when P2 joins, plus the idle, paused and win overlays (glyph art only — the win marker is the finish band's `▀▄▀▄` stripe). Read-only over the engine. |
| `ui/BoardView.qml` | One pane with one camera (camX/camY = world coords at the pane's top-left): platforms, both glyphs, the ghost trail, the orb, hazards, power-ups, the landing ripple, walk wobble, bump glow and the HUD tag (`P1 | ~ 3_100 | Ø 4`). Also holds the player glyph choices (`Ö` idle, `ö` asleep, `o` closed-eye, `Ô` glider, `Ø` death). A player outside the pane is pinned to the edge, dimmed and given a caret. |
| `ui/GlyphMetrics.qml` | The ink geometry of the text art: `TextMetrics` probes at pixelSize 100, the ratios they yield (platform per pattern and per row, line advance, player bottom/height, orb) and the lookups the view and the ripple use. Owns `artFontFeatures` (contextual alternates off) because what is measured has to be what is painted. Root is a zero-sized `Item` (QtObject has no default property for the probes). |
| `ui/LandRipple.qml` | The landing wave: a fixed pool of fixed cell grids, each cell an aligned overlay over the platform's *own* characters, coloured with the platform ink lifted in HSV. A ripple belongs to its platform, not to the pane: each slot keeps the camera it was fired against and re-derives its position from the pool's current camera. |
| `ui/ModeSelect.qml` | The mode picker overlay: lists `GameModes.js`, digits 1–9 pick, scaffolded modes show as soon. It owns the cursor (`cursorIndex` + `moveCursor`/`activateCursor`/`syncCursor`) but no focus: the keyboard and the pad both call those functions from outside, and the cursor resyncs to the playing mode every time the picker is shown. `moveCursor` steps to ready entries only and wraps. Row highlight is `hasCursor` (the shell's own cursor paint, as `ButtonGroup` uses), and hover moves the cursor so mouse and keys never disagree. |
| `ui/Confetti.qml` | The win shower: 64 character bits, paths derived from their index, running only while `running`. |
| `ui/Plain.js` | `plain()`: strips markup, control and bidi characters and caps the length. Used for strings handed to shell-rendered widgets (`tooltipText`, `PanelToolTip`), which use AutoText. |
| `ui/BarButton.qml` | The bar icon (`BarIconButton`): sizes its slot from the live label via `TextMetrics`, tooltip (mode + controller status), left click toggles the panel, right click asks for the reload menu. |
| `ui/ReloadMenu.qml` | The bar icon's right-click menu: reload the plugin (`omarchy-shell shell rescanPlugins`). |
| `ipc/DebugIpc.qml` | The `ojumpy.debug` surface: `state`, `dims`, `modes`, `course`, `start`, `mode`, `join`, `leave`, `pause`, `resume`, `fullscreen`. Read-only except the round controls, and all of it affects only the local game. Opening the panel needs no handler here: the shell gives every panel `open`/`close`/`toggle`/`show`/`hide` at the plugin's own target (`omarchy-shell ojumpy open`). |
| `audio/Sfx.qml` | Cue playback: probes for an audio CLI (argv-only `test -x`, absolute paths), a four-voice `Process` pool in round-robin so overlapping cues are not cut, and `play(cue)` picking one of the committed `sfx/*.wav` pitch variants. Silent unless the panel is open. |
| `audio/ojumpy-sfx.py` | The recipe for the committed cues: sweeps (`step`, `land`, `bump`, `jump`) and bell arpeggios (`orb`, `bing`), five pitch variants each. Run by hand (`python3 -B audio/ojumpy-sfx.py`); never at plugin startup, because writing here touches the folder the shell hot-reloads. |
| `input/ojumpy-pad.py` | The opt-in evdev bridge. Takes the event nodes udev classified as joysticks (`ID_INPUT_JOYSTICK` in `/run/udev/data`, with the kernel's `jsN` handler as fallback — no name matching), merges them into one 2-player state and prints one compact JSON line per change plus a 2 s heartbeat on stdout. Events are folded in by the pure `apply_event`, so the mapping is testable without hardware. Besides the per-player fields it publishes `up`/`down`/`confirm` for menus: any pad's D-pad, hat or either stick past the deadzone, and any pad's `A`. No state file. Logging is opt-in via `--log PATH` (appended 0600, `O_NOFOLLOW`). |
| `state/ojumpy-state.py` | State and theme IO, bound to descriptors: walks `~/.local/state/...` from the passwd home with held dirfds, refuses symlinked components, forces the plugin's own state directory to 0700 and removes non-regular entries in it, reads through one `O_NOFOLLOW|O_NONBLOCK` descriptor that is `fstat`-validated (regular, our uid, one link, within the cap), and writes an exclusive 0600 temporary that is fsynced and renamed over the destination. Modes: `state read`, `state write` (one bounded stdin line, validated against a closed schema), `theme read`. Failures exit non-zero with one line — a refused read is never treated as "absent, start fresh". |
| `state/ThemeStore.qml` | The active theme's palette: a watcher-only `FileView` plus one bounded descriptor read of `colors.toml` through the helper, parsed into `palette`, `green` and `color(role, fallback)`. `reload()` is also called when the panel opens, so a theme switch made while it was closed is picked up even if the watcher missed it. |

## Runtime state — NOT in the plugin folder, NOT committed

`~/.local/state/ojumpy/`

| File | Role |
|---|---|
| `game.json` | Chosen mode, per-mode best times, the manual's open state and the gamepad choice, e.g. `{"mode":"race","best":{"race":4190},"help":false,"pad":true}` — written and read only through `state/ojumpy-state.py`. |

One file, and nothing else is written here in this version: pad state is streamed
over stdout. The directory itself is 0700 and its contents are repaired on every
helper call — anything that is not a regular file is removed and the rest is forced
to 0600 — so a leftover `pad.json`/`sfx/` from an older version, a planted symlink
or a FIFO cannot stand in for the state document. Both leftovers are safe to delete
by hand.

**Why outside the plugin folder:** omarchy-shell watches the plugin directory and
reloads the plugin on any file change. State files change every couple of seconds —
writing them here caused an infinite reload loop.

## Theme integration

The palette comes from the active Omarchy theme
(`~/.local/state/omarchy/current/theme/colors.toml`): start pad and finish line
`foreground`, longest platform `dark_foreground`, middle `light_foreground`,
smallest `bright_foreground`, P1 `accent`, P2 `bright_cyan`; `green` (else
`bright_green`) drives the UI accents. UI scale follows the shell's rem scale
(`Style.spacing.scale`), so the game tracks the Omarchy font setting.

## Gamepad bridge

`input/ojumpy-pad.py`, started only while the panel's gamepad row is on.

| | Move left / right | Jump |
|---|---|---|
| **P1** (first pad) | left stick or D-pad | `A` |
| **P2** (second pad) | left stick or D-pad | `A`, `B` or `X` |
| **P2** (single pad) | right stick | `B` or `X` |
| round start | `Start` / `Select` / `Mode` on any pad | |

Devices are ordered by event path, so the first pad is P1 and the second is P2;
keyboard input is always mixed in. Full setup, pairing and troubleshooting:
`GAMEPAD.md`.
