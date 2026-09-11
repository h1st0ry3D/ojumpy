import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui"
import "core"
import "audio"
import "state"
import "ipc"
import "core/GameModes.js" as Modes

// Ojumpy — 2-player glyph race for the Omarchy bar.
//
// Architecture (split for extensibility):
//   GameEngine.qml  — simulation only, fixed base units (440x500). Scaling is a
//                     view concern, so fullscreen/resize never touches state.
//   Course.js       — seeded course generator (pure functions).
//   GameModes.js    — rules registry; new multiplayer modes = new entry.
//   GameBoard.qml   — arena layout: one BoardView, or two when P2 joins.
//   BoardView.qml   — one pane: platforms, players, ghosts, impact effects.
//   GamePanel.qml   — the drop-down card (chrome, board, buttons, accordion).
//   BarButton.qml   — the bar icon + tooltip.
//   ReloadMenu.qml  — the bar icon's right-click menu.
//   DebugIpc.qml    — the `ojumpy.debug` IPC surface.
//   Panel.qml       — this file: plugin state, palette, scale math and the tick
//                     (input aggregation + simulation). It owns no view ids; the
//                     card reports its chrome heights back for the sizing math.

Panel {
    id: root
    moduleName: "ojumpy"
    ipcTarget: "ojumpy"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property string home: Quickshell.env("HOME")
    // Both helpers live in the plugin folder and are run as argv arrays with an
    // absolute interpreter: a `python3` resolved through PATH can be shadowed by
    // anything on it, `-I -S` keeps the run out of the user's environment and
    // site-packages, and `-B` stops python writing __pycache__ into this
    // hot-reload-watched folder.
    readonly property string python: "/usr/bin/python3"
    readonly property url padHelperUrl: Qt.resolvedUrl("input/ojumpy-pad.py")
    readonly property string padHelperPath: decodeURIComponent(padHelperUrl.toString().replace(/^file:\/\//, ""))
    readonly property url stateHelperUrl: Qt.resolvedUrl("state/ojumpy-state.py")
    readonly property string stateHelperPath: decodeURIComponent(stateHelperUrl.toString().replace(/^file:\/\//, ""))
    // The theme file is only *watched* through this path; its contents are read
    // by the helper (see the theme block below).
    readonly property string themeColorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
    // consumer-side ceilings for the helper streams (the helpers enforce the
    // real byte caps)
    readonly property int stateMaxBytes: 65536
    readonly property int padLineMax: 512

    // ---- reactive sizing ----
    // shellScale = Omarchy rem scale ([font] base-size / 12 × [spacing] scale).
    // fsScaleX/Y = fullscreen boost from the dropdown's ACTUAL content size,
    // fitting inside the card's real inner area (padding + border insets, and
    // chrome heights on Y) so the arena never clips.
    readonly property real shellScale: Style.spacing.scale
    readonly property real _cardInsetW: 2 * (Style.spacing.popupPadding + Math.max(1, Style.normalBorderWidth))
    readonly property real _cardInsetH: 2 * (Style.spacing.popupPadding + Math.max(1, Style.normalBorderWidth))
    readonly property real _chromeH: dropdown.hdrRowH + dropdown.btnRowH + dropdown.helpSectionH
        + dropdown.padToggleH + 4 * Style.space(10) + 2 * Style.space(12)
    // Fullscreen keeps the panel's 440:500 aspect: the arena is fitted to the
    // available height and the width follows, centred in the screen — no
    // horizontal stretch, so world art and collision boxes always agree.
    readonly property real _fsHeightFit: Math.max(1,
        (dropdown.contentHeight - _cardInsetH - _chromeH) / (500 * root.shellScale))
    // board width in base units: 440 solo/split, 880 when fullscreen gives each
    // pane the whole arena width
    readonly property real _boardUnits: game.viewportW * (game.p2Joined ? 2 : 1)
    readonly property real _fsWidthFit: Math.max(1,
        (dropdown.contentWidth - _cardInsetW - Style.space(28)) / (_boardUnits * root.shellScale))
    readonly property real fsScaleY: root.fsFullscreen
        ? Math.min(root._fsHeightFit, root._fsWidthFit) : 1
    readonly property real fsScaleX: root.fsScaleY
    property real scaleX: root.shellScale * root.fsScaleX
    property real scaleY: root.shellScale * root.fsScaleY
    // uiScale = fullscreen boost ONLY (chrome fonts already follow shellScale
    // via Style.font.*). Derived from the *available* height, never from
    // contentHeight, so it cannot feed back into _chromeH (binding loop).
    readonly property real uiScale: root.fsFullscreen
        ? Math.min(2.0, Math.max(1.0, (dropdown.availableCardHeight - _cardInsetH)
                                       / (700 * root.shellScale)))
        : 1.0

    // Vertical room the "Ojumpy manual" block may use: whatever the card has
    // left, so nothing clips. Windowed the board is a fixed size and comes off
    // the top; fullscreen sizes the board from the leftover room itself
    // (_fsHeightFit), and reading the board height here would close a binding
    // loop through _chromeH/scaleY. Nothing left over simply means no room to
    // show text in — the card still fits.
    readonly property real _cardMaxH: dropdown.availableCardHeight
        // ...matching contentHeight above: the screen's usable height IS the cap
    readonly property real _helpBudget: Math.max(0,
        _cardMaxH - _cardInsetH - dropdown.hdrRowH - dropdown.btnRowH - dropdown.helpToggleH
        - dropdown.padToggleH - (root.fsFullscreen ? 0 : dropdown.boardSlotH)
        - 4 * Style.space(10) - 2 * Style.space(12) - Style.space(6) - Style.space(4))

    // fullscreen panes are full arena width (see GameEngine.viewportW)
    Binding { target: game; property: "wideView"; value: root.fsFullscreen }

    // Body of the "Ojumpy manual" accordion: label + value rows instead of one
    // prose block. It shares the card with the board, so it has to stay short
    // (five rows, each one line at normal sizes) and scannable; anything longer
    // wraps inside the row and the whole block scrolls (see _helpBudget).
    readonly property real helpLabelW: Math.ceil(56 * root.uiScale)
    readonly property var helpRows: [
        { k: "Mode", v: game.mode.name + " — " + game.mode.tagline },
        { k: "P1", v: "pad 1 stick / D-pad + A   ·   keys ←/→ + ↑/Enter" },
        { k: "P2", v: game.p2Joined
                       ? "pad 2 stick + A/B   ·   keys A/D + W/Space   ·   own camera"
                       : "J joins: pad 2 stick + A/B   ·   keys A/D + W/Space" },
        { k: "Moves", v: "double jump: tap jump again mid-air   ·   hold jump while falling to glide (Ô)" },
        { k: "Keys", v: "Enter/R start   ·   P pause   ·   S stop   ·   M modes   ·   F fullscreen   ·   Esc close" }
    ]

    // ---- ui state ----
    property bool fsFullscreen: false
    property bool _fsKeep: false
    property bool modesOpen: false
    property bool reloadMenuOpen: false
    // "Ojumpy manual" accordion at the bottom of the panel: closed by default
    // so the shortcut list is not in the way (persisted in game.json)
    property bool helpOpen: false
    // Controller support is opt-in: the evdev bridge is only started when this is
    // on, so a default install opens no input device at all and needs no `input`
    // group. The pad row in the panel toggles it (a user action) and the choice
    // is stored with the mode/best document.
    property bool padEnabled: false
    property var keysDown: ({})

    // ---- theme: palette roles for the course + chrome ----
    // ThemeStore.qml owns reading and watching colors.toml (watcher-only
    // FileView + one bounded descriptor read via ojumpy-state.py); the panel
    // only maps roles to course colours.
    ThemeStore {
        id: theme
        helperPath: root.stateHelperPath
        themePath: root.themeColorsPath
        python: root.python
    }
    function themeColor(key, fallback) { return theme.color(key, fallback) }

    // course palette:
    //   start pad + finish line  foreground  (inverse of the background)
    //   longest plat             dark_foreground
    //   middle plat              light_foreground
    //   smallest plat            bright_foreground
    //   player 1                 accent
    //   player 2                 bright_cyan
    readonly property color themeGreen: theme.green !== "" ? theme.green : "#2ECC71"
    readonly property color edgeColor: root.themeColor("foreground", Color.foreground)
    readonly property color platLongColor: root.themeColor("dark_foreground", Color.foreground)
    readonly property color platMidColor: root.themeColor("light_foreground", Color.foreground)
    readonly property color platSmallColor: root.themeColor("bright_foreground", Color.foreground)
    readonly property color p1Color: Color.accent
    readonly property color p2Color: root.themeColor("bright_cyan", Color.foreground)
    readonly property var platColors: [root.platSmallColor, root.platMidColor, root.platLongColor]

    // ---- pad bridge: stdlib evdev reader streaming one JSON line per update ----
    // The bridge prints a line per change; the panel consumes its own child's
    // stdout (no state file, no poll, no fixed path to plant something at),
    // capped per line and field-validated — a helper's output is still input.
    // `-u` keeps python from buffering the lines away.
    property var pad: ({p1x: 0, p1left: false, p1right: false, p1jump: false,
                        p2x: 0, p2left: false, p2right: false, p2jump: false,
                        start: false, connected: false, pads: 0})
    function padAxis(v) {
        var n = Number(v);
        if (!isFinite(n)) return 0;
        return n < -1 ? -1 : (n > 1 ? 1 : n);
    }
    function applyPadLine(line) {
        var s = String(line || "");
        if (s.length > root.padLineMax) return;          // reject, never truncate
        var d = null;
        try { d = JSON.parse(s); } catch (e) { return; }
        if (!d || typeof d !== "object") return;
        root.pad = {
            p1x: root.padAxis(d.p1x), p1left: !!d.p1left,
            p1right: !!d.p1right, p1jump: !!d.p1jump,
            p2x: root.padAxis(d.p2x), p2left: !!d.p2left,
            p2right: !!d.p2right, p2jump: !!d.p2jump,
            start: !!d.start, connected: !!d.connected,
            pads: Math.max(0, Math.min(8, Math.floor(Number(d.pads) || 0)))
        };
    }
    Process {
        id: padProc
        command: [root.python, "-I", "-S", "-B", "-u", root.padHelperPath]
        running: false          // only ever started by setPadEnabled(true)
        stdout: SplitParser {
            onRead: function (line) { root.applyPadLine(line) }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: if (root.padEnabled && !padProc.running) padProc.running = true;
    }

    // ---- persisted mode, best times and accordion state ----
    // Read once through the descriptor-bound helper (never `FileView.text()`),
    // written back the same way: a random 0600 temporary in the destination
    // directory, fsynced, renamed over the destination.
    property string stateBuf: ""
    property bool stateOverflow: false
    Process {
        id: stateRead
        command: [root.python, "-I", "-S", "-B", root.stateHelperPath, "state", "read"]
        running: true
        stdout: SplitParser {
            splitMarker: ""
            onRead: function (chunk) {
                if (root.stateBuf.length + chunk.length > root.stateMaxBytes) {
                    root.stateOverflow = true;
                    return;
                }
                if (!root.stateOverflow) root.stateBuf += chunk;
            }
        }
        onExited: function (code) {
            if (code === 0 && !root.stateOverflow) root.applyState(root.stateBuf);
            root.stateBuf = "";
            root.stateOverflow = false;
        }
    }
    function applyState(raw) {
        var d = null;
        try { d = JSON.parse(String(raw || "")); } catch (e) { return; }
        if (!d || typeof d !== "object") return;
        // a mode this build no longer has (or one renamed since) falls back to
        // the default instead of leaving the engine on a dead id — the next
        // write then heals the document
        if (d.mode) game.modeId = Modes.isReady(d.mode) ? d.mode : "race";
        if (d.best && typeof d.best === "object") {
            var best = {};
            for (var k in d.best) {
                var ms = Number(d.best[k]);
                // only modes this build knows: the document is closed schema
                if (Modes.isReady(k) && isFinite(ms) && ms >= 0 && ms < 1e9) best[k] = ms;
            }
            game.bestByMode = best;
        }
        root.helpOpen = !!d.help;
        root.padEnabled = !!d.pad;
        // the document said the user wants gamepads: start the reader now rather
        // than waiting for the watchdog timer
        if (root.padEnabled && !padProc.running) padProc.running = true;
    }
    Process {
        id: stateWrite
        command: [root.python, "-I", "-S", "-B", root.stateHelperPath, "state", "write"]
        stdinEnabled: true
        onStarted: {
            // the helper reads one bounded line, so this never needs EOF
            write(JSON.stringify({ mode: game.modeId, best: game.bestByMode,
                                   help: root.helpOpen, pad: root.padEnabled }) + "\n");
            stdinEnabled = false;
        }
    }
    function saveState() {
        stateWrite.running = false;
        stateWrite.running = true;    // onStarted writes the current document
    }

    // ---- engine ----
    GameEngine {
        id: game
        onRoundStarted: dropdown.focusGame()
        onRoundEnded: root.saveState()
        onBestByModeChanged: root.saveState()
        onModeIdChanged: root.saveState()
    }
    onHelpOpenChanged: root.saveState()

    // Starting/stopping the bridge is explicit, never a binding the restart
    // timer could fight with: the timer only re-starts what the user asked for,
    // and turning it off really stops the reader.
    function setPadEnabled(on) {
        root.padEnabled = !!on;
        padProc.running = false;
        if (root.padEnabled) padProc.running = true;
        root.saveState();
    }

    // ---- sound effects ----
    // Sfx.qml owns the cues, the player probe and the voice pool; the panel just
    // says when sound is allowed (while it is open — the sim keeps ticking in the
    // background, so a held pad button must not click footsteps out of the bar).
    Sfx {
        id: sfx
        game: game
        enabled: root.opened
    }

    function fmt(t) { return game.fmtTime(t); }

    // ---- input sources: keyboard (keysDown) + pad bridge ----
    function p1Left() {
        return !!root.keysDown[Qt.Key_Left] || !!root.pad.p1left || (Number(root.pad.p1x) || 0) < -0.35;
    }
    function p1Right() {
        return !!root.keysDown[Qt.Key_Right] || !!root.pad.p1right || (Number(root.pad.p1x) || 0) > 0.35;
    }
    function p1JumpHeld() {
        return !!root.keysDown[Qt.Key_Up] || !!root.keysDown[Qt.Key_Enter] || !!root.pad.p1jump;
    }
    function p2Left() {
        return !!root.keysDown[Qt.Key_A] || !!root.pad.p2left || (Number(root.pad.p2x) || 0) < -0.35;
    }
    function p2Right() {
        return !!root.keysDown[Qt.Key_D] || !!root.pad.p2right || (Number(root.pad.p2x) || 0) > 0.35;
    }
    function p2JumpHeld() {
        return !!root.keysDown[Qt.Key_W] || !!root.keysDown[Qt.Key_Space] || !!root.pad.p2jump;
    }

    // ---- reload (context menu) ----
    Process { id: reloadProc }
    function reloadNow() {
        reloadProc.command = ["omarchy-shell", "shell", "rescanPlugins"]
        reloadProc.running = false
        reloadProc.running = true
    }

    function toggleFullscreen() {
        // Pure view change: the engine lives in base units, so the level,
        // positions and timer survive untouched. No restart, no relayout.
        // F is the only fullscreen toggle; Esc just closes the panel.
        // _fsKeep marks the deliberate close+reopen below, so that close is not
        // mistaken for "the game went to the background" — set it only when the
        // reopen really follows, or a toggle from a closed panel would leave it
        // stuck on and disable the auto-pause.
        root._fsKeep = root.opened
        root.fsFullscreen = !root.fsFullscreen
        if (root.opened) { root.close(); root.toggle(); }
    }

    // ---- tick: pad start edge + feed inputs + simulate ----
    Timer {
        id: tick
        interval: 16; running: true; repeat: true
        onTriggered: {
            var s = !!root.pad.start;
            if (s && !root.padStartHeld && !root.modesOpen) {
                if (!game.roundActive) game.startRound();
            }
            root.padStartHeld = s;
            // P2 joins on J, or on a fresh P2 input (edge-triggered, so leaving
            // with a button held doesn't instantly re-join). Solo: P2 is inert.
            var p2in = root.p2Left() || root.p2Right() || root.p2JumpHeld();
            if (!game.p2Joined && p2in && !root.p2InputWas) game.joinP2();
            root.p2InputWas = p2in;
            // The panel is the only place the game is drawn, so a round must
            // never run while it is off-screen: whenever the panel is dismissed
            // (Esc, the ✕, clicking away, another panel taking over) a running
            // round freezes — a round just started from a pad while the panel was
            // already closed (or from the debug IPC) is caught here too, since
            // that path never sees an open->closed transition. Fullscreen closes
            // and reopens the panel on purpose to relayout (_fsKeep), so that one
            // close is excluded. pauseGame() is a no-op unless a round is live.
            if (!root.opened && !root._fsKeep) game.pauseGame();
            if (root.modesOpen) return;
            // tick() advances the sim only while a round is active; it always
            // settles the cameras, so the ready-state panes frame the spawns.
            game.p1Vx = (root.p1Right() ? 1 : 0) - (root.p1Left() ? 1 : 0);
            game.p1JumpHeld = root.p1JumpHeld();
            game.p2Vx = game.p2Joined ? ((root.p2Right() ? 1 : 0) - (root.p2Left() ? 1 : 0)) : 0;
            game.p2JumpHeld = game.p2Joined && root.p2JumpHeld();
            game.tick(0.016);
        }
    }

    property bool padStartHeld: false
    property bool p2InputWas: false

    // The palette arrives from ThemeStore asynchronously; nothing else has to
    // happen at startup (the store starts its own read).
    Component.onCompleted: theme.reload()

    onOpenedChanged: {
        if (opened === true) {
            dropdown.focusGame();
            root.modesOpen = false;
            root._fsKeep = false;
            // re-read the palette on open as well: the watcher covers live theme
            // switches, this covers anything it might have missed while closed
            theme.reload();
        }
        else {
            // (The auto-pause on a dismissed panel lives in the tick, so it also
            // covers rounds started while the panel was already closed.)
            if (!root._fsKeep && root.fsFullscreen) root.fsFullscreen = false;
        }
    }

    // ---- bar widget button ----
    // The live label is progress while a round runs ("99_100"), otherwise the two
    // glyphs ("ö_Ö"). BarButton.qml sizes the icon slot from it and owns the
    // tooltip; here we only keep the label and wire the two clicks.
    // Progress in the bar: the climb in the racing modes, player 1's score in the
    // collect modes (Glyph Hunt), and the idle glyphs otherwise.
    readonly property string barLabel: (game.roundActive && !game.paused)
        ? (game.scoreTarget > 0 ? (game.p1Score + "_" + game.scoreTarget)
                                : (game.p1Plat + "_" + (game.platforms.length - 1)))
        : "ö_Ö"

    BarButton {
        id: button
        game: game
        panel: root
        label: root.barLabel
        onReloadRequested: root.reloadMenuOpen = !root.reloadMenuOpen
    }

    // The bar button's right-click menu (see ReloadMenu.qml): it reports the
    // click back here so the flag can toggle, and hides itself after a reload.
    ReloadMenu {
        id: reloadMenu
        panel: root
        anchorButton: button
        openState: root.reloadMenuOpen
        onDismissed: root.reloadMenuOpen = false
        onReloadRequested: {
            root.reloadMenuOpen = false;
            root.reloadNow();
        }
    }

    // ---- dropdown panel: chrome + game board + mode overlay ----
    GamePanel {
        id: dropdown
        game: game
        panel: root
        anchorButton: button
    }

    DebugIpc {
        game: game
        panel: root
        dropdown: dropdown
    }
}
