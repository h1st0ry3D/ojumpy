import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../core/GameModes.js" as Modes
import "Plain.js" as Plain

// The drop-down panel: card chrome (header, board slot, action buttons, the
// collapsible controls list, the controller switch) with the win confetti and
// the game's keyboard shortcuts.
//
// `panel` is the plugin root: it owns the scale factors, the palette roles, the
// ui flags (modesOpen/helpOpen/fsFullscreen), the pad state and the help rows,
// so this component stays view-only and the panel can still answer `dims` with
// the card metrics.
// ---- dropdown panel: chrome + game board + mode overlay ----
KeyboardPanel {
    id: gamePanel

    required property var game        // GameEngine
    required property var panel       // Panel root
    required property var anchorButton

    // ---- measurements the panel's sizing math needs ----
    // The chrome lives here, so the card reports its own heights instead of the
    // panel reaching into ids it no longer owns (that used to raise
    // ReferenceErrors for hdrRow/btnRow/helpToggle/boardSlot/gameFocus).
    readonly property real hdrRowH: hdrRow.height
    readonly property real btnRowH: btnRow.height
    readonly property real helpSectionH: helpSection.height
    readonly property real helpToggleH: helpToggle.height
    readonly property real padToggleH: padToggle.height
    readonly property real boardSlotH: boardSlot.height
    function focusGame() { gameFocus.forceActiveFocus() }

    // The mode picker's cursor, driven from outside: Panel's key handler calls
    // these directly, Panel's tick calls them on pad edges. The picker itself
    // stays passive (it has no focus, so it never competes for keys).
    function modeMoveCursor(delta) { modeSelect.moveCursor(delta) }
    function modeActivateCursor() { modeSelect.activateCursor() }
    anchorItem: gamePanel.anchorButton
    owner: panel
    bar: panel.bar
    open: panel.opened
    focusTarget: gameFocus
    contentWidth: panel.fsFullscreen ? gamePanel.availableCardWidth : gamePanel.fittedContentWidth(Style.space(480))
    // Height cap: the shell's own "what fits on screen" figure, with no
    // smaller limit — the arena (500 units) plus chrome is tall, and a lower
    // cap would squeeze the info block on tall screens.
    contentHeight: panel.fsFullscreen ? dropdown.availableCardHeight
                                    : gamePanel.fittedContentHeight(col.implicitHeight)

    // ---- win confetti across the whole panel (fullscreen = whole screen) ----
    // Held back 1 s after the round is won (ROUND_CLEAR_HOLD_TIME):
    // the glyph grows and lights up first, *then* the shower starts, and the
    // verdict card follows 2 s in — GameBoard runs that timer, this one the
    // confetti. A new round clears both.
    Confetti {
        anchors.fill: parent
        z: 6
        running: gamePanel.confettiOn
        palette: panel.platColors.concat([panel.p1Color, panel.p2Color, panel.edgeColor])
        scale: panel.uiScale
    }
    property bool confettiOn: false
    // Hidden non-visual items live in their own zero-sized Item: this panel's
    // default property is contentItem, so a bare Timer would be treated as an
    // item to lay out and the card would fail to load.
    Item {
        width: 0
        height: 0
        Timer {
            id: confettiDelay
            interval: 1000
            onTriggered: gamePanel.confettiOn = true
        }
        Connections {
            target: game
            // any win: the orb (racing modes) or the tenth glyph (Glyph Hunt)
            function onRoundEnded(playerIdx, timeSec) { confettiDelay.restart() }
            function onRoundStarted() { confettiDelay.stop(); gamePanel.confettiOn = false }
        }
    }

    Item {
        id: gameFocus
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (event.isAutoRepeat) { panel.keysDown[event.key] = true; return; }
            panel.keysDown[event.key] = true;
            if (event.key === Qt.Key_Escape) {
                if (panel.modesOpen) { panel.modesOpen = false; }
                else panel.close();
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_M) { panel.modesOpen = !panel.modesOpen; event.accepted = true; return; }
            if (panel.modesOpen) {
                // the picker owns Up/Down/Enter while it is open: the sim is not
                // ticked in that state, so no key is taken away from the game
                if (event.key === Qt.Key_Up) { dropdown.modeMoveCursor(-1); event.accepted = true; return; }
                if (event.key === Qt.Key_Down) { dropdown.modeMoveCursor(1); event.accepted = true; return; }
                if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                    dropdown.modeActivateCursor(); event.accepted = true; return;
                }
            }
            if (panel.modesOpen && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                var list = Modes.list();
                var idx = event.key - Qt.Key_1;
                if (idx < list.length && list[idx].ready) {
                    game.modeId = list[idx].id;
                    panel.modesOpen = false;
                }
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_R) {
                if (panel.modesOpen) panel.modesOpen = false;
                game.startRound(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_J) {
                game.toggleP2(); event.accepted = true; return;
            }
            // Enter is player 2's jump (solo: P1's as well) while a round is live,
            // but from the ready screen it starts a round — nothing can be jumped
            // there anyway. A *finished* round is deliberately not included: at the
            // win, Enter is exactly the button the players are mashing, and R is
            // the rematch key.
            if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)
                && !panel.modesOpen && !game.roundActive && game.winner === "") {
                game.startRound(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_S) {
                game.stopGame(); panel.modesOpen = false; event.accepted = true; return;
            }
            if (event.key === Qt.Key_P) {
                game.togglePause(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_F) {
                panel.toggleFullscreen(); event.accepted = true; return;
            }
        }
        Keys.onReleased: function(event) {
            if (!event.isAutoRepeat) delete panel.keysDown[event.key];
        }

        Column {
            id: col
            width: parent.width
            spacing: Style.space(10)
            topPadding: Style.space(12)
            bottomPadding: Style.space(12)
            leftPadding: Style.space(14)
            rightPadding: Style.space(14)

            Item {
                id: hdrRow
                width: parent.width - Style.space(28)
                height: Math.max(hdrContent.height, fsBtn.height, closeBtn.height)

                // Header text cluster. The three texts run at three different font
                // sizes (heading / title / body) and used to each centre their own
                // box in the row, which left "best" floating a few units above the
                // other two. They share ONE baseline here instead: the title is the
                // tallest box and the reference, the smaller two are hung off its
                // baseline by their own baselineOffset. `best` follows the status,
                // which is hidden while the game is ready/stopped (a hidden Text
                // takes no room, unlike an empty one, which would still space out).
                Item {
                    id: hdrContent
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real gap: Style.space(10)
                    // `baseline` itself is a FINAL Item property (used by QML
                    // Layouts), so the reference offset needs its own name.
                    readonly property real textBaseline: titleText.baselineOffset
                    width: bestText.x + bestText.width
                    height: titleText.height

                    Text {
                        id: titleText
                        x: 0
                        y: 0
                        textFormat: Text.PlainText
                        // The header title is just the mode. The old
                        // "Ojumpy solo" / "Ojumpy O_O" prefix repeated what the
                        // board already shows (pane tags, and the
                        // Splitscreen/Solo button), and the mode is what you
                        // actually re-check when you sit down.
                        text: game.mode.name
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.heading * panel.uiScale
                        font.bold: true
                    }
                    Text {
                        id: hdrStatus
                        x: titleText.width + hdrContent.gap
                        y: Math.round(hdrContent.textBaseline - baselineOffset)
                        textFormat: Text.PlainText
                        // Status only: the clock while running, the win time after a
                        // win, and nothing in the ready/stopped state — the mode name
                        // that "ready — …" used to carry is the title now. The two
                        // markers are Nerd Font glyphs (Font Awesome, the family the
                        // header icons already use), never emoji: the UI is text art,
                        // so a colour emoji next to it always looked pasted in.
                        text: game.roundActive ? "\uf017  " + panel.fmt(game.elapsed)
                            : (game.winner !== "" ? "\uf11e  " + panel.fmt(game.winTime) : "")
                        visible: text !== ""
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title * panel.uiScale
                        font.bold: true
                    }
                    Text {
                        id: bestText
                        x: hdrStatus.x + hdrStatus.width + hdrContent.gap
                        y: Math.round(hdrContent.textBaseline - baselineOffset)
                        textFormat: Text.PlainText
                        text: "best " + (game.bestFor(game.modeId) >= 0 ? (game.bestFor(game.modeId) / 1000).toFixed(2) + "s" : "--")
                        color: panel.themeGreen
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body * panel.uiScale
                    }
                }

                PanelActionButton {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // The X needs a bigger font than the fullscreen brackets to read
                    // as the same size (the glyph is drawn smaller within its em), so
                    // the icon grows while `size` is pinned to the fullscreen
                    // button's box — otherwise the taller font would also grow the
                    // 22x22 button and shift the whole header.
                    iconText: "\uf00d"
                    fontSize: Style.font.icon * 1.3
                    size: fsBtn.size
                    tooltipText: "Close the panel (Esc)"
                    foreground: panel.themeGreen
                    onClicked: panel.close()
                }

                PanelActionButton {
                    id: fsBtn
                    anchors.right: closeBtn.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\uf065"
                    tooltipText: "Fullscreen (F)"
                    foreground: panel.themeGreen
                    onClicked: panel.toggleFullscreen()
                }
            }

            Item {
                id: boardSlot
                width: parent.width - Style.space(28)
                height: game.baseH * panel.scaleY

                GameBoard {
                    id: board
                    anchors.centerIn: parent
                    engine: game
                    scaleX: panel.scaleX
                    scaleY: panel.scaleY
                    themeGreen: panel.themeGreen
                    edgeColor: panel.edgeColor
                    platColors: panel.platColors
                    p1Color: panel.p1Color
                    p2Color: panel.p2Color
                    uiScale: panel.uiScale
                }

                ModeSelect {
                    id: modeSelect
                    anchors.fill: board
                    engine: game
                    uiScale: panel.uiScale
                    themeGreen: panel.themeGreen
                    visible: panel.modesOpen
                    onPicked: {
                        panel.modesOpen = false;
                        game.startRound();
                    }
                }
            }

            // Buttons carry the action only: the keyboard shortcut lives in
            // the tooltip (qs.Ui Button renders tooltipText on hover).
            Row {
                id: btnRow
                width: parent.width - Style.space(28)
                spacing: Style.space(8)
                Button {
                    text: game.roundActive ? "Stop" : "Start"
                    tooltipText: game.roundActive ? "Stop the round (S)"
                                 : "Start a round (R / Enter / pad Start)"
                    fontSize: Style.font.body * panel.uiScale
                    onClicked: game.roundActive ? game.stopGame() : game.startRound()
                }
                Button {
                    text: "Mode"
                    tooltipText: "Pick a mode (M)"
                    fontSize: Style.font.body * panel.uiScale
                    onClicked: panel.modesOpen = !panel.modesOpen
                }
                Button {
                    // The labels name the layout, not the player: one pane or two.
                    // Joining/leaving is what the button does, split/solo is what
                    // you get — and "Solo" also reads as the way out of a split.
                    text: game.p2Joined ? "Solo" : "Splitscreen"
                    tooltipText: game.p2Joined
                        ? "Player 2 drops out: back to one pane (J)"
                        : "Player 2 joins: two panes, one camera each (J)"
                    fontSize: Style.font.body * panel.uiScale
                    onClicked: game.toggleP2()
                }
                Button {
                    text: "Restart"
                    tooltipText: "Restart the course with a fresh seed (R)"
                    fontSize: Style.font.body * panel.uiScale
                    onClicked: { panel.modesOpen = false; game.startRound() }
                }
                Button {
                    // Pause takes the row slot the ✕ used to hold: closing moved up
                    // into the header, next to fullscreen. Closing the panel (or
                    // anything else that hides it) pauses a running round anyway,
                    // so the two actions now agree instead of competing.
                    text: game.paused ? "Resume" : "Pause"
                    tooltipText: game.paused
                        ? "Resume the round (P / pad Start)"
                        : "Pause the round — rocks and the clock freeze (P / pad Start)"
                    enabled: game.roundActive
                    fontSize: Style.font.body * panel.uiScale
                    onClicked: game.togglePause()
                }
            }

            // ---- controls & info: collapsed by default ----
            // This is where the shortcut list lives (the buttons above only
            // carry it in their tooltips), so the bottom of the panel stays
            // quiet until it is asked for. The open/closed state is kept in
            // game.json with the mode and the best times.
            Item {
                id: helpSection
                width: parent.width - Style.space(28)
                height: helpCol.height

                Column {
                    id: helpCol
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                        id: helpToggle
                        width: parent.width
                        leftAlign: true
                        text: (panel.helpOpen ? "▾  " : "▸  ") + "Ojumpy Manual"
                        tooltipText: panel.helpOpen ? "Hide the controls and rules"
                                                   : "Show the controls and rules"
                        fontSize: Style.font.body * panel.uiScale
                        onClicked: panel.helpOpen = !panel.helpOpen
                    }

                    // the shortcut list can be long, so it scrolls inside
                    // the room left over rather than pushing the card's
                    // content past its height (see _helpBudget)
                    ScrollView {
                        id: helpScroll
                        visible: panel.helpOpen
                        width: parent.width
                        height: Math.min(helpList.implicitHeight, panel._helpBudget)
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: helpList.implicitHeight > helpScroll.height
                            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        Binding {
                            target: helpScroll.contentItem
                            property: "interactive"
                            value: helpList.implicitHeight > helpScroll.height
                        }

                        Column {
                            id: helpList
                            width: helpScroll.availableWidth
                            spacing: Math.round(3 * panel.uiScale)

                            Repeater {
                                model: panel.helpRows
                                delegate: Item {
                                    required property var modelData
                                    width: helpList.width
                                    height: Math.max(helpKey.implicitHeight,
                                                     helpValue.implicitHeight)

                                    Text {
                                        textFormat: Text.PlainText
                                        id: helpKey
                                        text: modelData.k
                                        color: panel.themeGreen
                                        font.family: "monospace"
                                        font.pixelSize: 11 * panel.uiScale
                                        font.bold: true
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        id: helpValue
                                        x: panel.helpLabelW
                                        width: parent.width - panel.helpLabelW
                                        wrapMode: Text.WordWrap
                                        text: modelData.v
                                        color: Util.alpha(Color.foreground, 0.8)
                                        font.family: "monospace"
                                        font.pixelSize: 11 * panel.uiScale
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Controller support: the status and the opt-in switch in one row.
            // Off by default — reading /dev/input/event* is a capability the
            // user asks for by clicking, so nothing is opened before that.
            // Text goes through Plain.plain: qs.Ui renders button labels.
            Button {
                id: padToggle
                width: parent.width - Style.space(28)
                leftAlign: true
                text: Plain.plain(!panel.padEnabled
                      ? "○ gamepad off — keyboard only   (click to enable)"
                      : (panel.pad && panel.pad.connected
                         ? "● gamepad x" + panel.pad.pads + " — click to disable"
                         : "● gamepad on — no device readable (permissions?)"))
                tooltipText: panel.padEnabled
                    ? "Stop reading gamepads"
                    : "Read gamepads (see GAMEPAD.md — usually no setup needed)"
                fontSize: 11 * panel.uiScale
                onClicked: panel.setPadEnabled(!panel.padEnabled)
            }
        }
    }
}
