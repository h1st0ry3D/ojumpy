# Ojumpy — gamepad guide

Xbox / XInput-style pads on Omarchy. Keyboard play needs none of this: gamepad
support is opt-in, and the whole setup is the driver (for the pads that need one)
plus one click in the panel. No privileged command, no udev rule, no group.

## Driver

| Pad | What provides it | What you do |
|---|---|---|
| Xbox 360, wired Xbox One | `xpad`, in the kernel | nothing |
| Xbox One S / Series, Xbox Elite, over Bluetooth | `xpadneo-dkms` | install it once, then pair |
| Xbox wireless dongle | the same package on most setups | install it; if the pad still does not appear, see *Troubleshooting* |

Omarchy ships that case in its own menu: **Install → Gaming → Xbox Controllers**
(`omarchy-install-gaming-xbox-controllers`), which brings in `xpadneo-dkms`,
`dkms` and the kernel headers and builds the module.

Check it is in place: `pacman -Q xpadneo-dkms`, and `lsmod | grep xpadneo` while a
pad is connected (nothing there with no pad attached is normal). Either way the
kernel ends up exposing the pad as a joystick node — something like
`/dev/input/event21 'Xbox Wireless Controller'`.

## Turn gamepad reading on

Open the panel from the bar, expand **Ojumpy Manual**, click the gamepad row:

| Row reads | Meaning |
|---|---|
| `○ gamepad off — keyboard only   (click to enable)` | the bridge is not running; no input device is opened |
| `● gamepad x1 — click to disable` / `x2` | that many pads are being read |
| `● gamepad on — no device readable (permissions?)` | the bridge runs but sees no pad node — connect or pair it, or see *Troubleshooting* |

The choice is remembered in `~/.local/state/ojumpy/game.json`, so it survives
closing the panel, a shell reload and a reboot. Clicking the row again stops the
reader process.

Access itself is the desktop's: udev marks joystick devices and logind gives the
active session user an ACL on them (`70-uaccess.rules`). The bridge reads exactly
the devices udev classified as joysticks — never keyboards or mice.

## Connect

**USB** — plug it in. The bridge rescans every 3 s, so a pad connected after the
panel was opened is picked up on its own.

**Bluetooth** — use the shell's Bluetooth panel, or type this at the
`[bluetooth]#` prompt (the address comes from `scan on`):

```
bluetoothctl
power on
agent on
default-agent
scan on
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
connect XX:XX:XX:XX:XX:XX
scan off
```

`trust` is what makes it reconnect by itself later. The pad has to be in its
Xbox/XInput mode — the default for Xbox pads, and the `X` position on 8BitDo-style
pads; DInput/Switch modes are not read.

**Check what the game sees** — the bridge logs every node it takes:

```bash
journalctl --user -t omarchy-shell | grep ojumpy-pad
# ojumpy-pad: watching /dev/input/event21 'Xbox Wireless Controller'
```

## Mapping

Devices are ordered by event path: the **first** pad drives P1, the **second**
drives P2. Keyboard input is always live alongside, so keyboard and pad can drive
the same player.

| | Move left / right | Jump |
|---|---|---|
| **P1** (first pad) | left stick **or** D-pad | **A** |
| **P2** (second pad) | left stick **or** D-pad | **A**, **B** or **X** |
| **P2** (only one pad) | right stick | **B** or **X** |

On the keyboard the split is WASD + `Space` for P1 and arrows + `Enter` for P2
(solo: both drive P1) — see the *Controls* table in the [README](README.md).

Movement is not analog: a stick past ~35 % counts as a direction, a D-pad press as
full deflection. Pushing P2's controls mid-round splits the screen.

| Button | What it does |
|---|---|
| **A** | jump (P1; also the picker's confirm) |
| **B**, **X** | jump for P2 (on a single pad) |
| **Start** | pause / resume |
| **Select**, **Mode** | open or close the mode picker |
| **R3** (click the right stick) | fullscreen, like `F` |
| D-pad ↑/↓, either stick | move the picker's highlight; **A** picks |

Starting a round is the picker's job on a pad: `Select`, then `A` — picking the mode
that is already playing starts a fresh round rather than doing nothing. There is no
rumble, and the button map is fixed: see the end of this file.

Everything else (jump, double jump, glide, shoves, the goal of each mode) is the
same on a pad as on the keyboard — see the *Playing* and *Controls* sections of
the [README](README.md).

## Troubleshooting

| Symptom | Check |
|---|---|
| Row says `● gamepad on — no device readable (permissions?)` | is the pad visible to the kernel at all? `cat /proc/bus/input/devices` should list it and `ls /dev/input/js*` should exist. Nothing there means a driver or pairing problem, not a game problem |
| Bluetooth pad pairs, then drops | `systemctl status bluetooth`, and pair it with `trust` so it reconnects |
| Dongle pad not detected | `lsusb` shows the dongle? `lsmod \| grep xpadneo`? Some dongle models need the driver's own quirks — check its documentation |
| Module never loads (pad attached, `lsmod` empty) | `dkms status` — a kernel upgrade without headers leaves the module unbuilt; reinstall the Omarchy Xbox Controllers item |
| Pad works elsewhere, the game sees nothing | the row must be on (`● gamepad x…`), and the pad must be joystick-classified: `ID_INPUT_JOYSTICK=1` in `/run/udev/data/c<major>:<minor>` (that is the exact test the bridge makes) |
| Left stick drifts, the racer walks alone | the stick's centre is off; the deadzone is 35 % — recentre or recalibrate |
| Two pads, both drive P1 | devices are ordered by event path; unplug and replug the second pad |
| Nothing in the journal | start the bridge by hand (below) |

Run the bridge by hand to watch it work: it prints one JSON state line per change
on stdout, and `--log` appends the raw evdev events (file created 0600, never
following a symlink):

```bash
/usr/bin/python3 -I -S -B ~/.config/omarchy/plugins/ojumpy/input/ojumpy-pad.py \
  --log ~/.local/state/ojumpy/pad.log
```

Ctrl-C stops it. Turn the panel's gamepad row off first if you do not want two
readers at once.

## Privacy and scope

- Reads **only** devices udev classified as joysticks, and only while the gamepad
  row is on. Keyboards, mice, touchpads, webcams and every other input node are
  never opened.
- Keeps the current button and axis state in memory. Nothing is recorded, and the
  state is streamed to the panel over the bridge's own stdout — there is no state
  file for a pad.
- Writes nothing unless you pass `--log PATH` yourself.
- No network, no privilege, no service, no group.

## Changing the mapping

There is no rebinding UI; the mapping is constants at the top of
`input/ojumpy-pad.py`: `BTN_SOUTH`/`BTN_EAST`/`BTN_WEST`/`BTN_NORTH`
(304/305/308/307) for the face buttons, `ABS_X`/`ABS_RX`/`ABS_HAT0X` for the axes,
`BTN_START`/`BTN_SELECT`/`BTN_MODE` (315/314/316) for pause and the picker,
`BTN_THUMBR` (318) for fullscreen, and the menu's up/down (`BTN_DPAD_UP`/`DOWN`
544/545, `ABS_HAT0Y`, `ABS_Y`/`ABS_RY`). Edit and save — the
shell hot-reloads the plugin folder, so the next panel open uses the new map. A
local edit is yours alone: `omarchy plugin update ojumpy` restores the committed
version, so commit a remap in your own fork if you want to keep it.
