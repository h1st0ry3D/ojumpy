import QtQuick
import Quickshell.Io

// The active theme's palette.
//
// `Color.*` only exposes background/foreground/accent/muted/urgent, so the extra
// roles the course needs come from the theme's own colors.toml. The file is not
// ours, and a pathname read could follow a symlink or block on a FIFO: the
// FileView is a watcher only (it never hands over bytes) and the read itself is
// a bounded descriptor read in ojumpy-state.py.
//
// Root is a zero-sized Item because QtObject has no default property for the
// FileView/Process children.
Item {
    id: store
    width: 0
    height: 0

    required property string helperPath   // ojumpy-state.py
    required property string themePath    // .../current/theme/colors.toml (watched only)
    property string python: "/usr/bin/python3"
    readonly property int maxBytes: 65536

    property var palette: ({})            // role -> "#rrggbb"
    property string green: ""             // green, else bright_green, else ""

    // A palette role, or the fallback when the theme does not define it.
    function color(key, fallback) {
        var v = store.palette[key];
        return (typeof v === "string" && v.charAt(0) === "#") ? v : fallback;
    }

    FileView {
        id: themeWatch
        path: store.themePath
        preload: false
        blockAllReads: true
        watchChanges: true
        printErrors: false
        onFileChanged: store.reload()
    }

    property string buf: ""
    property bool overflow: false

    // Read the palette now. Also called when the panel opens, so a theme switch
    // that happened while the panel was closed is picked up even if the watcher
    // missed it.
    function reload() {
        themeRead.running = false;
        themeRead.running = true;
    }

    Process {
        id: themeRead
        command: [store.python, "-I", "-S", "-B", store.helperPath, "theme", "read"]
        running: true
        stdout: SplitParser {
            splitMarker: ""              // raw chunks: the byte budget is counted here
            onRead: function (chunk) {
                if (store.buf.length + chunk.length > store.maxBytes) {
                    store.overflow = true;
                    return;
                }
                if (!store.overflow) store.buf += chunk;
            }
        }
        onExited: function (code) {
            if (code === 0 && !store.overflow) store.parse(store.buf);
            store.buf = "";
            store.overflow = false;
        }
    }

    function parse(raw) {
        var txt = String(raw || "");
        var found = {};
        var lines = txt.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (m) found[m[1]] = m[2];
        }
        store.palette = found;           // reassign so bindings re-evaluate
        var g = txt.match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/m);
        var b = txt.match(/^\s*bright_green\s*=\s*["']?(#[0-9A-Fa-f]{6})/m);
        store.green = g ? g[1] : (b ? b[1] : "");
    }
}
