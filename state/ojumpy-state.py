#!/usr/bin/python3
"""Ojumpy state and theme I/O, bound to descriptors (stdlib only).

Why this exists instead of FileView: a pathname is not an object. Reading a
predictable path with `FileView`, `cat`, `open(path)` or `json.load(open(path))`
follows a symlink someone else planted, blocks forever on a planted FIFO, and
pulls the whole file into the shell process before any size check runs. The
shell is one long-lived process hosting every widget, so it is the last thing on
the desktop that may block or allocate without bound.

So every read and write here goes through a descriptor that is validated and
then used:

  * directories are walked from the passwd home one component at a time with
    held dirfds, each component `O_NOFOLLOW|O_DIRECTORY`, `fstat`-checked for
    owner and type; the plugin's own leaf is forced to 0700 and its contents
    repaired (anything that is not a regular file is removed, files get 0600)
  * reads open `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, `fstat` the descriptor (regular
    file, our uid, one link, owner-only mode, size) and read at most
    MAX_BYTES + 1 bytes, so oversize is an error rather than a truncation
  * writes create a fresh random 0600 file with `O_CREAT|O_EXCL|O_NOFOLLOW` in
    the destination directory, write through that descriptor, `fsync`, then
    `rename` over the destination (which replaces a symlink instead of writing
    through it) and `fsync` the directory

Modes:

    ojumpy-state.py state read     # -> the saved mode/best/help document
    ojumpy-state.py state write    # <- the same document on stdin
    ojumpy-state.py theme read     # -> the active Omarchy theme's colors.toml

The write mode validates that stdin is a JSON object and that it only carries
the keys this plugin stores, so a corrupted or hostile document is refused
rather than installed. Every failure is a non-zero exit: nothing falls back to
"absent, so start fresh".
"""
import json
import os
import pwd
import re
import secrets
import stat
import sys

MAX_BYTES = 65536          # state document ceiling (it is a few hundred bytes)
THEME_MAX_BYTES = 65536    # colors.toml ceiling
_COMPONENT = re.compile(r"[A-Za-z0-9._-]+")
_STATE_NAME = "game.json"

# plugin state: ~/.local/state/ojumpy  (created if missing, forced 0700)
STATE_CHAIN = (".local", "state", "ojumpy")
# theme read: ~/.local/state/omarchy/current/theme/colors.toml (read-only, not
# ours: the chain is only validated, never re-moded or repaired)
THEME_CHAIN = (".local", "state", "omarchy", "current", "theme")
THEME_FILE = "colors.toml"


def _ok_component(name):
    return bool(_COMPONENT.fullmatch(name)) and name not in (".", "..")


def _repair_dir(dir_fd):
    """Make the plugin's own directory trustworthy: no symlinks, FIFOs or
    subdirectories inside it, and owner-only modes on what stays. Runs on every
    call, because a directory that is 0700 today can still hold a 0644 file or
    an entry somebody else put there."""
    for entry in os.listdir(dir_fd):
        try:
            st = os.stat(entry, dir_fd=dir_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if not stat.S_ISREG(st.st_mode):
            try:
                if stat.S_ISDIR(st.st_mode):
                    os.rmdir(entry, dir_fd=dir_fd)
                else:
                    os.unlink(entry, dir_fd=dir_fd)
            except OSError:
                pass
            continue
        if st.st_mode & 0o077:
            try:
                os.chmod(entry, 0o600, dir_fd=dir_fd, follow_symlinks=False)
            except OSError:
                pass


def open_dir_chain(parts, create_missing=False, repair_leaf=False):
    """Walk `parts` under the passwd home with held descriptors, return the
    final dirfd. $HOME is not trusted as an anchor (a same-UID child can point
    it anywhere), so the home comes from passwd; the home itself may be a
    symlink, so the anchor is not opened O_NOFOLLOW."""
    if not parts or not all(_ok_component(p) for p in parts):
        raise PermissionError("refusing directory chain")
    home = pwd.getpwuid(os.geteuid()).pw_dir
    fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for i, name in enumerate(parts):
            leaf = i == len(parts) - 1
            try:
                nfd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=fd)
            except FileNotFoundError:
                # Our own state path (.local/state/ojumpy) is created on demand, a
                # component at a time, 0700: a fresh machine has to work, and the
                # foreign theme chain stays strictly read-only.
                if not create_missing:
                    raise
                os.mkdir(name, 0o700, dir_fd=fd)
                nfd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=fd)
            os.close(fd)
            fd = nfd
            st = os.fstat(fd)
            if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
                raise PermissionError("untrusted directory component: %s" % name)
            if leaf and repair_leaf:
                if st.st_mode & 0o077:
                    os.fchmod(fd, 0o700)
                _repair_dir(fd)
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_bounded(dir_fd, name, limit=MAX_BYTES):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     dir_fd=dir_fd)
    except FileNotFoundError:
        return None
    try:
        st = os.fstat(fd)
        if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_nlink != 1
                or st.st_size > limit):
            raise PermissionError("refusing %s: not a plain owner-only file within %d bytes"
                                  % (name, limit))
        os.set_blocking(fd, True)
        data = b""
        while len(data) <= limit:
            chunk = os.read(fd, min(65536, limit + 1 - len(data)))
            if not chunk:
                break
            data += chunk
        if len(data) > limit:
            raise PermissionError("%s grew past the limit" % name)
        return data
    finally:
        os.close(fd)


def write_atomic(dir_fd, name, data):
    if len(data) > MAX_BYTES:
        raise ValueError("payload too large")
    tmp = ".%s.%s.tmp" % (name, secrets.token_hex(8))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                 0o600, dir_fd=dir_fd)
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fsync(fd)
        os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        os.fsync(dir_fd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dir_fd)
        except OSError:
            pass
        raise
    finally:
        os.close(fd)


def clean_state(payload):
    """The document is written by this plugin, but it is still input: keep the
    known keys with the expected shapes and drop everything else."""
    if not isinstance(payload, dict):
        raise ValueError("state must be a JSON object")
    out = {}
    mode = payload.get("mode")
    if isinstance(mode, str) and _ok_component(mode):
        out["mode"] = mode
    best = payload.get("best")
    if isinstance(best, dict):
        clean = {}
        for k, v in list(best.items())[:64]:
            if isinstance(k, str) and _ok_component(k) and isinstance(v, (int, float)) \
                    and not isinstance(v, bool) and 0 <= v < 1e9:
                clean[k] = int(v)
        out["best"] = clean
    out["help"] = bool(payload.get("help"))
    # Controller support is opt-in and therefore a stored preference: a missing
    # key means off, so a fresh install never reads an input device at all.
    out["pad"] = bool(payload.get("pad"))
    return out


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("state", "theme") or sys.argv[2] != "read":
        if len(sys.argv) != 3 or sys.argv[1] != "state" or sys.argv[2] != "write":
            sys.stderr.write("usage: ojumpy-state.py state read|write | theme read\n")
            return 2

    if sys.argv[1] == "state":
        dir_fd = open_dir_chain(STATE_CHAIN, create_missing=True, repair_leaf=True)
        try:
            if sys.argv[2] == "read":
                raw = read_bounded(dir_fd, _STATE_NAME)
                if raw is None:
                    return 0
                sys.stdout.write(raw.decode("utf-8", "strict"))
                return 0
            # one bounded line, not read-to-EOF: the caller writes the document
            # and a newline, and a caller that forgets to close the pipe must not
            # be able to leave this process waiting forever on a save
            payload = sys.stdin.buffer.readline(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES:
                sys.stderr.write("state write: payload too large\n")
                return 3
            if not payload.strip():
                sys.stderr.write("state write: empty document\n")
                return 3
            clean = clean_state(json.loads(payload.decode("utf-8", "strict")))
            write_atomic(dir_fd, _STATE_NAME, json.dumps(clean, separators=(",", ":")).encode())
            return 0
        finally:
            os.close(dir_fd)

    # theme: the active Omarchy palette, read-only through a validated chain
    dir_fd = open_dir_chain(THEME_CHAIN)
    try:
        raw = read_bounded(dir_fd, THEME_FILE, THEME_MAX_BYTES)
        if raw is None:
            return 0
        sys.stdout.write(raw.decode("utf-8", "replace"))
        return 0
    finally:
        os.close(dir_fd)


if __name__ == "__main__":
    # A refused read/write is an error, not "absent, so start fresh": exit
    # non-zero with one line a human can read rather than a traceback.
    try:
        sys.exit(main())
    except (PermissionError, OSError, ValueError) as e:
        sys.stderr.write("ojumpy-state: %s\n" % e)
        sys.exit(1)
