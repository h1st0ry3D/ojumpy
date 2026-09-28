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
// `panel` is the plugin root and owns the scale factors, palette roles, ui
// flags, pad state and help rows; this component stays view-only and reports
// its chrome heights back for the panel's sizing math.
KeyboardPanel {
    id: gamePanel

    required property var game        // GameEngine
    required property var panel       // Panel root
    required property var anchorButton

    // ---- measurements the panel's sizing math needs ----
    // the chrome lives here, so the card reports its own heights
    readonly property real hdrRowH: hdrRow.height
    readonly property real btnRowH: btnRow.height
    readonly property real helpSectionH: helpSection.height
    readonly property real helpToggleH: helpToggle.height
    readonly property real padToggleH: padToggle.height
    readonly property real boardSlotH: boardSlot.height
    function focusGame() { gameFocus.forceActiveFocus() }

    // the mode picker's cursor, driven from outside: Panel's key handler and
    // tick call these, and the picker has no focus, so it never competes for keys
    function modeMoveCursor(delta) { modeSelect.moveCursor(delta) }
    function modeActivateCursor() { modeSelect.activateCursor() }
    anchorItem: gamePanel.anchorButton
    owner: panel
    bar: panel.bar
    open: panel.opened
    focusTarget: gameFocus
    contentWidth: panel.fsFullscreen ? gamePanel.availableCardWidth : gamePanel.fittedContentWidth(Style.space(480))
    // Height cap: the shell's own "what fits on screen" figure, with no smaller
    // limit. The arena (500 units) plus chrome is tall, and a lower cap squeezes
    // the info block.
    contentHeight: panel.fsFullscreen ? dropdown.availableCardHeight
                                    : gamePanel.fittedContentHeight(col.implicitHeight)

    // ---- win confetti across the whole panel (fullscreen = whole screen) ----
    // Held back 1 s after the win (ROUND_CLEAR_HOLD_TIME) so the glyph beat
    // lands first; GameBoard runs the 2 s verdict delay, this one the shower.
    // Any win fires it: the orb (racing modes) or the tenth glyph (Glyph Hunt).
    Confetti {
        anchors.fill: parent
        z: 6
        running: gamePanel.confettiOn
        palette: panel.platColors.concat([panel.p1Color, panel.p2Color, panel.edgeColor])
        scale: panel.uiScale
    }
    property bool confettiOn: false
    // hidden non-visual items need their own zero-sized Item: the default
    // property is contentItem, so a bare Timer would be laid out and fail
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
                // the picker owns Up/Down/Enter while it is open; the sim is not
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
            // Enter is P2's jump (solo: P1's too) while a round is live, but from
            // the ready screen it starts one. A *finished* round is left to R: at
            // the win, Enter is what the players are mashing.
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

                // Header text cluster. The three texts share one baseline instead
                // of each centring its own box: the title is the tallest box and
                // the reference, the smaller two hang off its baselineOffset.
                Item {
                    id: hdrContent
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real gap: Style.space(10)
                    // `baseline` is a final Item property (used by QML Layouts),
                    // so the reference offset needs its own name.
                    readonly property real textBaseline: titleText.baselineOffset
                    width: bestText.x + bestText.width
                    height: titleText.height

                    Text {
                        id: titleText
                        x: 0
                        y: 0
                        textFormat: Text.PlainText
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
                        // Status only: clock while running, win time after a win,
                        // nothing in ready/stopped. A hidden Text takes no room,
                        // where an empty one would still space `best` out.
                        // The markers are Nerd Font glyphs, never emoji.
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
                    // the X is drawn smaller within its em, so its font scales up to
                    // match the brackets; `size` stays pinned to the fullscreen
                    // button's box, or the taller font grows the button too
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

            // the keyboard shortcut lives in the tooltip, not on the button face
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

                    // scrolls inside the room left over rather than pushing the
                    // card's content past its height (see _helpBudget)
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
            // text goes through Plain.plain: qs.Ui renders button labels
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
