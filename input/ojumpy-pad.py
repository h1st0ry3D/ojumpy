#!/usr/bin/env python3
"""Ojumpy Xbox-controller bridge (stdlib only).

Reads Linux evdev event devices directly, merges all gamepad-like
devices into one virtual 2-player state and streams it to Panel.qml as one
compact JSON line per change (plus a 2 s heartbeat), on stdout — there is no
state file and no path for anyone to plant anything at.

Mapping (single Xbox pad hosts both racers):
  P1 (0) move : left stick X  (ABS_X) + D-pad X (HAT0X / BTN_DPAD_*)
  P1 (0) jump : A (BTN_SOUTH, 304)
  P2 (8) move : right stick X (ABS_RX) + D-pad X when 2nd pad present
  P2 (8) jump : B (BTN_EAST, 305), alt X (BTN_WEST, 308)
  round start : Start (315) / Select (314) / Mode (316), rising edge
  menus       : up/down = D-pad Y, hat Y or either stick's Y past the
                deadzone, confirm = A, on ANY pad (rising edges)
  Start (315) : pause, on any pad (rising edge)
  Select (314) / Mode (316): open/close the mode picker, on any pad
  R3 (318)    : fullscreen, on any pad (rising edge; panel must be open)

Second physical pad (if any): its left stick + A feed P2 as well, so
2 pads = 1 racer each. Everything merges, no config needed.

Access to /dev/input/event* is the desktop's own grant: udev tags joystick
devices and logind gives the active session user an ACL on them, so on an
Omarchy install nothing has to be set up. No third-party deps, and no state
file is written — the panel reads this process's stdout.
"""
import argparse
import glob
import json
import os
import re
import select
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y, ABS_RX, ABS_RY = 0, 1, 3, 4
ABS_HAT0X, ABS_HAT0Y = 16, 17
BTN_SOUTH, BTN_EAST = 304, 305
BTN_NORTH, BTN_WEST = 307, 308
BTN_TL, BTN_TR = 310, 311
BTN_SELECT, BTN_START, BTN_MODE = 314, 315, 316
BTN_THUMBL, BTN_THUMBR = 317, 318          # L3 / R3: clicking the sticks
BTN_DPAD_UP, BTN_DPAD_DOWN, BTN_DPAD_LEFT, BTN_DPAD_RIGHT = 544, 545, 546, 547

# A device is a gamepad when the *desktop* says so: udev records the answer in
# /run/udev/data, and ID_INPUT_JOYSTICK is the same property that makes logind
# give the active session access. So the game reads exactly what the desktop
# granted, with no name matching or capability guessing to keep in sync.
#
# Scope: Xbox/XInput pads (in-kernel xpad; xpadneo for Xbox One/Series over
# Bluetooth or the dongle) — what ID_INPUT_JOYSTICK covers on an Omarchy box.
MAX_UDEV_BYTES = 1 << 16


def parse_devices():
    """Map event handler -> {name, js} from /proc/bus/input/devices.

    Only the name (for logs) and whether the kernel gave the device a joystick
    handler (the fallback classification when udev's database is unreadable) are
    needed; capability bitmaps are not parsed because device selection is udev's
    job (see udev_props / is_gamepad)."""
    try:
        # kernel file, fixed path (nothing can plant a symlink in /proc), read
        # with a ceiling anyway so this can never grow into the shell's memory
        with open("/proc/bus/input/devices", errors="replace") as f:
            text = f.read(1 << 20)
    except OSError:
        return {}
    devs, cur = {}, {}
    for line in text.splitlines() + [""]:
        if not line.strip():
            if cur.get("events"):
                for ev in cur["events"]:
                    devs[ev] = {"name": cur.get("name", ""), "js": cur.get("js", False)}
            cur = {}
            continue
        if line.startswith("N:"):
            m = re.search(r'Name="([^"]*)"', line)
            cur["name"] = m.group(1) if m else ""
        elif line.startswith("H:"):
            cur["events"] = re.findall(r"event\d+", line)
            # jsN handler = real joystick node; Consumer Control/Keyboard/Mouse
            # halves of a composite pad have no jsN and must not take a slot.
            cur["js"] = bool(re.search(r"\bjs\d+\b", line))
    return devs


def udev_props(path):
    """The properties udev recorded for this event node, or {} when there is
    none to read. /run/udev/data is udev's own database (world-readable, managed
    by udevd, keyed by the device's major:minor) — reading it is not a guess
    about the device, it is the desktop's own answer."""
    try:
        st = os.stat(path)
        key = "/run/udev/data/c%d:%d" % (os.major(st.st_rdev), os.minor(st.st_rdev))
        with open(key, errors="replace") as f:
            data = f.read(MAX_UDEV_BYTES)
    except OSError:
        return {}
    props = {}
    for line in data.splitlines():
        if line.startswith("E:"):
            name, _, value = line[2:].partition("=")
            props[name] = value
    return props


def is_gamepad(info, props):
    """Joystick by udev's classification (and therefore by the ACL logind gave
    this session), or — when udev's database is unavailable — by the kernel's
    own: only joystick-class devices get a jsN handler."""
    if props.get("ID_INPUT_JOYSTICK") == "1":
        return True
    return bool(info.get("js"))


def open_devices():
    infos = parse_devices()
    paths = sorted(glob.glob("/dev/input/event*"))
    opened = []
    for path in paths:
        ev = os.path.basename(path)
        info = infos.get(ev)
        if info is None:
            # not in /proc/bus/input/devices: nothing to classify it by, skip
            continue
        if not is_gamepad(info, udev_props(path)):
            continue
        try:
            # read-only, non-blocking (the reader must never stall on a node),
            # close-on-exec, and no following of anything at the path
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW)
        except OSError as e:
            print(f"ojumpy-pad: cannot open {path} ({info['name']}): {e}",
                  file=sys.stderr)
            continue
        opened.append({"fd": fd, "path": path, "name": info["name"]})
        print(f"ojumpy-pad: watching {path} '{info['name']}'", file=sys.stderr)
    return opened


class PadState:
    """Per-device state — one instance per opened event node."""

    def __init__(self):
        self.lx = 0.0
        self.ly = 0.0
        self.rx = 0.0
        self.ry = 0.0
        self.hatx = 0
        self.haty = 0
        self.dpad_l = False
        self.dpad_r = False
        self.dpad_u = False
        self.dpad_d = False
        self.a = False
        self.b = False
        self.x = False
        self.start = False
        self.select = False
        self.r3 = False

    def left_x(self):
        v = self.lx if abs(self.lx) >= 0.35 else 0.0
        if self.hatx != 0:
            v = float(self.hatx)
        if self.dpad_l and not self.dpad_r:
            v = -1.0
        elif self.dpad_r and not self.dpad_l:
            v = 1.0
        return max(-1.0, min(1.0, v))

    def right_x(self):
        v = self.rx if abs(self.rx) >= 0.35 else 0.0
        return max(-1.0, min(1.0, v))

    # Vertical moves are menus only (the racers move on X alone), so these
    # answer "is this pad asking to go up?" from every source at once: a
    # horizontal axis has to pick one source, a menu does not. Linux pads
    # report up as negative on both the sticks and the hat.
    def up_pressed(self):
        return bool(self.dpad_u or self.haty < 0
                    or self.ly <= -0.35 or self.ry <= -0.35)

    def down_pressed(self):
        return bool(self.dpad_d or self.haty > 0
                    or self.ly >= 0.35 or self.ry >= 0.35)


def merge_payload(pads, names):
    """pads: per-device PadState list in stable device order (sorted path).

    2+ pads: pad0 drives P1, pad1 drives P2 — each with its own left stick,
    D-pad and A/B/X buttons. 1 pad only: left stick/D-pad/A = P1,
    right stick/B/X = P2 (single-pad party mode).
    Start/Select/Mode on ANY pad starts the round.
    """
    if not pads:
        return disconnected()
    first = pads[0]
    p1x = first.left_x()
    if len(pads) >= 2:
        second = pads[1]
        p2x = second.left_x()
        p2jump = bool(second.a or second.b or second.x)
    else:
        p2x = first.right_x()
        p2jump = bool(first.b or first.x)
    return {
        "p1x": round(p1x, 3),
        "p1left": bool(p1x < -0.35),
        "p1right": bool(p1x > 0.35),
        "p1jump": bool(first.a),
        "p2x": round(p2x, 3),
        "p2left": bool(p2x < -0.35),
        "p2right": bool(p2x > 0.35),
        "p2jump": p2jump,
        # Start pauses; Select/Mode opens the mode picker (Panel decides)
        "pause": bool(any(s.start for s in pads)),
        "menu": bool(any(s.select for s in pads)),
        "fullscreen": bool(any(s.r3 for s in pads)),
        # menus (mode picker): any pad may drive them, any source that means up
        "up": bool(any(s.up_pressed() for s in pads)),
        "down": bool(any(s.down_pressed() for s in pads)),
        "confirm": bool(any(s.a for s in pads)),
        "connected": True,
        "pads": len(names),
        "names": names[:4],
    }


def norm(v):
    return max(-1.0, min(1.0, v / 32768.0))


def apply_event(state, etype, code, value):
    """Fold one evdev event into a pad's state (pure, so the mapping can be
    tested without a device). Unknown codes are ignored on purpose: a pad
    reports plenty of things this game has no use for."""
    if etype == EV_ABS:
        if code == ABS_X:
            state.lx = norm(value)
        elif code == ABS_Y:
            state.ly = norm(value)
        elif code == ABS_RX:
            state.rx = norm(value)
        elif code == ABS_RY:
            state.ry = norm(value)
        elif code == ABS_HAT0X:
            state.hatx = max(-1, min(1, value))
        elif code == ABS_HAT0Y:
            state.haty = max(-1, min(1, value))
    elif etype == EV_KEY:
        pressed = bool(value)
        if code == BTN_SOUTH:
            state.a = pressed
        elif code == BTN_EAST:
            state.b = pressed
        elif code in (BTN_WEST, BTN_NORTH):
            state.x = pressed
        elif code == BTN_START:
            state.start = pressed          # Panel: pause
        elif code in (BTN_SELECT, BTN_MODE):
            state.select = pressed         # Panel: mode picker
        elif code == BTN_THUMBR:
            state.r3 = pressed             # Panel: fullscreen
        elif code == BTN_DPAD_LEFT:
            state.dpad_l = pressed
        elif code == BTN_DPAD_RIGHT:
            state.dpad_r = pressed
        elif code == BTN_DPAD_UP:
            state.dpad_u = pressed
        elif code == BTN_DPAD_DOWN:
            state.dpad_d = pressed


def disconnected():
    return {"p1x": 0.0, "p1left": False, "p1right": False, "p1jump": False,
            "p2x": 0.0, "p2left": False, "p2right": False, "p2jump": False,
            "up": False, "down": False, "confirm": False,
            "pause": False, "menu": False, "fullscreen": False,
            "connected": False, "pads": 0, "names": []}


def emit(state):
    """One compact JSON line per update, flushed.

    There is deliberately no state file: a fixed path plus a reader in the shell
    is a symlink/FIFO hazard and needs a poll or inotify to stay fresh. A pipe
    has none of that — the panel reads its own child's stdout, one line at a
    time."""
    try:
        sys.stdout.write(json.dumps(state, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except (OSError, ValueError):
        pass          # panel went away (shell reload); the restart timer brings us back


def log_line(logf, text):
    """Opt-in debug log (-–log PATH), off by default: per-event file I/O adds
    input latency. Opened O_NOFOLLOW|O_APPEND|O_CREAT at mode 0600 so it can
    neither follow a planted symlink nor be world-readable."""
    if not logf:
        return
    try:
        fd = os.open(logf, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600)
        try:
            os.write(fd, f"{time.strftime('%H:%M:%S')} {text}\n".encode("utf-8", "replace"))
        finally:
            os.close(fd)
    except OSError as e:
        print(f"ojumpy-pad: log failed: {e}", file=sys.stderr)


def log_event(logf, dev_name, etype, code, value):
    log_line(logf, f"{dev_name} type={etype} code={code} value={value}")


def log_state(logf, state):
    log_line(logf, "STATE " + json.dumps(state, sort_keys=True))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default="")  # disabled by default: per-event file I/O adds input latency; pass a path to enable
    ap.add_argument("--scan-interval", type=float, default=3.0)
    ap.add_argument("--hz", type=float, default=60.0)
    args = ap.parse_args()

    devs = open_devices()
    states = {d["fd"]: PadState() for d in devs}
    last_write, last_scan = 0.0, time.monotonic()
    # the panel gets a first line immediately, so it never renders an unknown pad
    emit(disconnected())
    last_payload = json.dumps(disconnected(), sort_keys=True)

    while True:
        now = time.monotonic()
        if now - last_scan >= args.scan_interval:
            last_scan = now
            current = {d["path"] for d in devs}
            fresh = open_devices()
            fresh_paths = {d["path"] for d in fresh}
            for d in devs:
                if d["path"] not in fresh_paths:
                    try:
                        os.close(d["fd"])
                    except OSError:
                        pass
            for d in fresh:
                if d["path"] not in current:
                    devs.append(d)
                    states[d["fd"]] = PadState()
                else:
                    try:
                        os.close(d["fd"])
                    except OSError:
                        pass
            devs.sort(key=lambda d: d["path"])
            for d in devs:
                states.setdefault(d["fd"], PadState())

        fds = [d["fd"] for d in devs]
        if fds:
            fd_name = {d["fd"]: d["name"] for d in devs}
            try:
                r, _, _ = select.select(fds, [], [], 1.0 / args.hz)
            except (OSError, ValueError):
                r = []
            for fd in r:
                try:
                    data = os.read(fd, 64 * 24)
                except OSError:
                    data = b""
                if not data:
                    continue
                s = states.get(fd)
                if s is None:
                    continue
                for off in range(0, len(data) - 23, 24):
                    try:
                        _type, code, value = struct.unpack_from("HHi", data, off + 16)
                    except struct.error:
                        break
                    log_event(args.log, fd_name.get(fd, "?"), _type, code, value)
                    apply_event(s, _type, code, value)
        else:
            time.sleep(1.0 / args.hz)

        names = [d["name"] for d in devs]
        payload = (merge_payload([states[d["fd"]] for d in devs], names)
                   if devs else disconnected())
        blob = json.dumps(payload, sort_keys=True)
        if blob != last_payload or now - last_write > 2.0:
            emit(payload)
            log_state(args.log, payload)
            last_payload, last_write = blob, now


if __name__ == "__main__":
    main()
