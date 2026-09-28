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
import "core/Keys.js" as Keys

// Ojumpy — 2-player glyph race for the Omarchy bar.
//
// Architecture (split for extensibility):
//   GameEngine.qml  — simulation only, fixed base units (440x500); scaling is a
//                     view concern, so fullscreen/resize never touches state.
//   Course.js / GameModes.js — seeded course generator, rules registry.
//   GameBoard.qml / BoardView.qml — arena layout, one pane.
//   GamePanel.qml / BarButton.qml / ReloadMenu.qml — card, bar icon, its menu.
//   DebugIpc.qml    — the `ojumpy.debug` IPC surface.
//   Panel.qml       — plugin state, palette, scale math, the tick. Owns no view
//                     ids; the card reports its chrome heights back.

Panel {
    id: root
    moduleName: "ojumpy"
    ipcTarget: "ojumpy"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property string home: Quickshell.env("HOME")
    // Both helpers run as argv arrays with an absolute interpreter: a `python3`
    // resolved through PATH can be shadowed by anything on it, `-I -S` keeps the
    // run out of the user's environment and site-packages, and `-B` stops python
    // writing __pycache__ into this hot-reload-watched folder.
    readonly property string python: "/usr/bin/python3"
    readonly property url padHelperUrl: Qt.resolvedUrl("input/ojumpy-pad.py")
    readonly property string padHelperPath: decodeURIComponent(padHelperUrl.toString().replace(/^file:\/\//, ""))
    readonly property url stateHelperUrl: Qt.resolvedUrl("state/ojumpy-state.py")
    readonly property string stateHelperPath: decodeURIComponent(stateHelperUrl.toString().replace(/^file:\/\//, ""))
    // watched, not read: the contents come from ThemeStore's helper (see below)
    readonly property string themeColorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
    // consumer-side ceilings; the helpers enforce the real byte caps
    readonly property int stateMaxBytes: 65536
    readonly property int padLineMax: 512

    // ---- reactive sizing ----
    // shellScale = Omarchy rem scale ([font] base-size / 12 × [spacing] scale).
    // fsScaleX/Y = fullscreen boost fitted into the card's real inner area
    // (padding + border insets, chrome heights on Y) so the arena never clips.
    readonly property real shellScale: Style.spacing.scale
    readonly property real _cardInsetW: 2 * (Style.spacing.popupPadding + Math.max(1, Style.normalBorderWidth))
    readonly property real _cardInsetH: 2 * (Style.spacing.popupPadding + Math.max(1, Style.normalBorderWidth))
    readonly property real _chromeH: dropdown.hdrRowH + dropdown.btnRowH + dropdown.helpSectionH
        + dropdown.padToggleH + 4 * Style.space(10) + 2 * Style.space(12)
    // Fullscreen keeps the panel's 440:500 aspect: the arena is fitted to the
    // available height and the width follows, centred in the screen, with no
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
    // left. The board takes the top when windowed, the leftover room when
    // fullscreen. No room means no text; the card still fits.
    readonly property real _cardMaxH: dropdown.availableCardHeight
        // ...matching contentHeight above: the screen's usable height IS the cap
    readonly property real _helpBudget: Math.max(0,
        _cardMaxH - _cardInsetH - dropdown.hdrRowH - dropdown.btnRowH - dropdown.helpToggleH
        - dropdown.padToggleH - (root.fsFullscreen ? 0 : dropdown.boardSlotH)
        - 4 * Style.space(10) - 2 * Style.space(12) - Style.space(6) - Style.space(4))

    Binding { target: game; property: "wideView"; value: root.fsFullscreen }

    // Manual rows, label + value, five of them: the block shares the card with
    // the board, and a longer value wraps inside its row and scrolls.
    readonly property real helpLabelW: Math.ceil(56 * root.uiScale)
    readonly property var helpRows: [
        { k: "Mode", v: game.mode.name + " — " + game.mode.tagline },
        { k: "P1", v: "keys A/D + W or Space" + (game.p2Joined ? "" : "   ·   solo: also ←/→ + ↑ or Enter")
                       + "   ·   pad 1 stick / D-pad + A" },
        { k: "P2", v: game.p2Joined
                       ? "keys ←/→ + ↑ or Enter   ·   pad 2 stick + A/B/X   ·   own camera"
                       : "not in the round — J, or a pad's P2 buttons, joins" },
        { k: "Moves", v: "double jump: tap jump again mid-air   ·   hold jump while falling to glide (the hat: Ô / Û)"
                       + (game.mode.matchFall === true
                          ? "   ·   Match or Fall: E switches you between the two platform colours"
                            + (game.p2Joined ? " (P2: .)" : "") : "") },
        { k: "Keys", v: "R (or Enter) start   ·   P pause   ·   S stop   ·   M modes   ·   F fullscreen   ·   Esc close"
                       + "   ·   pad: Start start/pause, Select modes, R3 fullscreen" }
    ]

    // ---- ui state ----
    property bool fsFullscreen: false
    property bool _fsKeep: false
    property bool modesOpen: false
    property bool reloadMenuOpen: false
    // persisted in game.json with the mode and best times
    property bool helpOpen: false
    // Opt-in: the evdev bridge starts only when this is on, so a default install
    // opens no input device and needs no `input` group. Persisted with the
    // mode/best document.
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

    // course palette: start pad + finish line = foreground (the inverse of the
    // background), longest plat = dark_foreground, middle = light_foreground,
    // smallest = bright_foreground, P1 = accent, P2 = bright_cyan
    readonly property color themeGreen: theme.green !== "" ? theme.green : "#2ECC71"
    readonly property color edgeColor: root.themeColor("foreground", Color.foreground)
    readonly property color platLongColor: root.themeColor("dark_foreground", Color.foreground)
    readonly property color platMidColor: root.themeColor("light_foreground", Color.foreground)
    readonly property color platSmallColor: root.themeColor("bright_foreground", Color.foreground)
    readonly property color p1Color: Color.accent
    readonly property color p2Color: root.themeColor("bright_cyan", Color.foreground)
    readonly property var platColors: [root.platSmallColor, root.platMidColor, root.platLongColor]

    // ---- pad bridge: stdlib evdev reader streaming one JSON line per update ----
    // stdout of this panel's own child process, capped per line and field-
    // validated: a helper's output is still input. `-u` unbuffers the lines.
    property var pad: ({p1x: 0, p1left: false, p1right: false, p1jump: false,
                        p2x: 0, p2left: false, p2right: false, p2jump: false,
                        p1form: false, p2form: false,
                        up: false, down: false, confirm: false,
                        pause: false, menu: false, fullscreen: false,
                        connected: false, pads: 0})
    // axes are clamped through core/Keys.js, the same helper the layout uses,
    // so both agree on what a stick value means
    function applyPadLine(line) {
        var s = String(line || "");
        if (s.length > root.padLineMax) return;          // reject, never truncate
        var d = null;
        try { d = JSON.parse(s); } catch (e) { return; }
        if (!d || typeof d !== "object") return;
        root.pad = {
            p1x: Keys.axis(d, "p1x"), p1left: !!d.p1left,
            p1right: !!d.p1right, p1jump: !!d.p1jump,
            p2x: Keys.axis(d, "p2x"), p2left: !!d.p2left,
            p2right: !!d.p2right, p2jump: !!d.p2jump,
            p1form: !!d.p1form, p2form: !!d.p2form,
            up: !!d.up, down: !!d.down, confirm: !!d.confirm,
            pause: !!d.pause, menu: !!d.menu, fullscreen: !!d.fullscreen,
            connected: !!d.connected,
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
    // read and written through the descriptor-bound helper, never
    // `FileView.text()`: a write is a random 0600 temp, fsync, rename
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
        // a mode this build no longer has falls back to the default rather than
        // a dead id; the next write heals the document
        if (d.mode) game.modeId = Modes.isReady(d.mode) ? d.mode : "race";
        if (d.best && typeof d.best === "object") {
            var best = {};
            for (var k in d.best) {
                var ms = Number(d.best[k]);
                // closed schema: only modes this build knows
                if (Modes.isReady(k) && isFinite(ms) && ms >= 0 && ms < 1e9) best[k] = ms;
            }
            game.bestByMode = best;
        }
        root.helpOpen = !!d.help;
        root.padEnabled = !!d.pad;
        // skip the watchdog: start the reader now if the document asked for pads
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
        stateWrite.running = true;    // onStarted writes the document
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

    // explicit, not a binding the restart timer could fight with
    function setPadEnabled(on) {
        root.padEnabled = !!on;
        padProc.running = false;
        if (root.padEnabled) padProc.running = true;
        root.saveState();
    }

    // ---- sound effects ----
    // Sfx.qml owns the cues, the probe and the voice pool; the panel only says
    // when sound is allowed (while it is open, though the sim keeps ticking).
    Sfx {
        id: sfx
        game: game
        enabled: root.opened
    }

    function fmt(t) { return game.fmtTime(t); }

    // ---- input sources: keyboard (keysDown) + pad bridge ----
    // the key/pad layout lives in core/Keys.js; these wrappers only feed it the
    // live key set, the pad state and whether P2 is in the round
    function p1Left() { return Keys.p1Left(root.keysDown, root.pad, game.p2Joined); }
    function p1Right() { return Keys.p1Right(root.keysDown, root.pad, game.p2Joined); }
    function p1JumpHeld() { return Keys.p1Jump(root.keysDown, root.pad, game.p2Joined); }
    function p2Left() { return Keys.p2Left(root.keysDown, root.pad); }
    function p2Right() { return Keys.p2Right(root.keysDown, root.pad); }
    function p2JumpHeld() { return Keys.p2Jump(root.keysDown, root.pad); }
    function p1FormHeld() { return Keys.p1Form(root.keysDown, root.pad, game.p2Joined); }
    function p2FormHeld() { return Keys.p2Form(root.keysDown, root.pad); }
    function p2PadInput() { return Keys.p2PadInput(root.pad); }

    // ---- reload (context menu) ----
    Process { id: reloadProc }
    function reloadNow() {
        reloadProc.command = ["omarchy-shell", "shell", "rescanPlugins"]
        reloadProc.running = false
        reloadProc.running = true
    }

    function toggleFullscreen() {
        // View-only: the engine lives in base units, so the level, positions and
        // timer survive untouched. F is the only fullscreen toggle; Esc closes.
        // _fsKeep marks the close+reopen below so the tick's auto-pause skips it:
        // set it only when the reopen really follows, or a toggle from a closed
        // panel would leave it stuck on.
        root._fsKeep = root.opened
        root.fsFullscreen = !root.fsFullscreen
        if (root.opened) { root.close(); root.toggle(); }
    }

    // ---- tick: pad start edge + feed inputs + simulate ----
    Timer {
        id: tick
        interval: 16; running: true; repeat: true
        onTriggered: {
            // Pad buttons, all rising edges: Start pauses a live round or starts
            // one from the ready screen, Select opens the mode picker, R3
            // fullscreen. A finished round is left to R and Select → A; fullscreen
            // is ignored while the panel is shut (the flag is cleared on close).
            var pPause = !!root.pad.pause, pMenu = !!root.pad.menu;
            var pFs = !!root.pad.fullscreen;
            if (pPause && !root.padPauseWas) {
                if (game.roundActive) game.togglePause();
                else if (!root.modesOpen && game.winner === "") game.startRound();
            }
            if (pMenu && !root.padMenuWas) root.modesOpen = !root.modesOpen;
            if (pFs && !root.padFsWas && root.opened) root.toggleFullscreen();
            root.padPauseWas = pPause; root.padMenuWas = pMenu; root.padFsWas = pFs;
            // P2 joins on J, or on a fresh *pad* P2 input (edge-triggered, so
            // leaving with a button held cannot re-join). See p2PadInput().
            var p2in = root.p2PadInput();
            if (!game.p2Joined && p2in && !root.p2InputWas) game.joinP2();
            root.p2InputWas = p2in;
            // The panel is the only place the game is drawn, so a round must never
            // run off-screen: any dismissal pauses it, which also catches a round
            // started while the panel was already closed. pauseGame() is a no-op
            // unless a round is live; _fsKeep skips the fullscreen toggle's close.
            if (!root.opened && !root._fsKeep) game.pauseGame();
            // The mode picker takes the pad's vertical axis and A while it is
            // open. The "was" flags update every tick, so a button held from
            // before cannot act the instant it opens.
            var mUp = !!root.pad.up, mDown = !!root.pad.down, mOk = !!root.pad.confirm;
            if (root.modesOpen) {
                if (mUp && !root.padUpWas) dropdown.modeMoveCursor(-1);
                if (mDown && !root.padDownWas) dropdown.modeMoveCursor(1);
                if (mOk && !root.padConfirmWas) dropdown.modeActivateCursor();
            }
            root.padUpWas = mUp; root.padDownWas = mDown; root.padConfirmWas = mOk;
            if (root.modesOpen) return;
            // tick() advances the sim only while a round is active; it always
            // settles the cameras, so the ready-state panes frame the spawns.
            game.p1Vx = (root.p1Right() ? 1 : 0) - (root.p1Left() ? 1 : 0);
            game.p1JumpHeld = root.p1JumpHeld();
            game.p2Vx = game.p2Joined ? ((root.p2Right() ? 1 : 0) - (root.p2Left() ? 1 : 0)) : 0;
            game.p2JumpHeld = game.p2Joined && root.p2JumpHeld();
            // the colour switch rides the same path: the engine edge-detects it
            game.p1FormHeld = root.p1FormHeld();
            game.p2FormHeld = game.p2Joined && root.p2FormHeld();
            game.tick(0.016);
        }
    }

    property bool padPauseWas: false
    property bool padMenuWas: false
    property bool padFsWas: false
    property bool p2InputWas: false
    property bool padUpWas: false
    property bool padDownWas: false
    property bool padConfirmWas: false

    // the store starts its own read; the palette arrives asynchronously
    Component.onCompleted: theme.reload()

    onOpenedChanged: {
        if (opened === true) {
            dropdown.focusGame();
            root.modesOpen = false;
            root._fsKeep = false;
            // re-read on open too: covers what the watcher missed while closed
            theme.reload();
        }
        else {
            if (!root._fsKeep && root.fsFullscreen) root.fsFullscreen = false;
        }
    }

    // ---- bar widget button ----
    // Bar widget label: the climb, or player 1's score in the collect modes, while
    // a round runs; the idle glyphs otherwise. A paused round keeps its progress
    // (see BarButton.qml, which measures this label).
    readonly property string barLabel: game.roundActive
        ? (game.scoreTarget > 0 ? (game.p1Score + "_" + game.scoreTarget)
                                : (game.p1Plat + "_" + (game.platforms.length - 1)))
        : "Ö_Ü"

    BarButton {
        id: button
        game: game
        panel: root
        label: root.barLabel
        onReloadRequested: root.reloadMenuOpen = !root.reloadMenuOpen
    }

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
        sfx: sfx
    }
}
