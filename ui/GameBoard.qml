import QtQuick
import qs.Commons

// Ojumpy game board — viewport layout over the shared engine state.
//
// Solo: one BoardView over the whole arena (camX1/camY1). Player 2 joins (J):
// two side-by-side views split by a vertical divider, left = P1's camera,
// right = P2's, and both panes render both players.
//
// Resizing/fullscreen never disturbs the game: the engine simulates in fixed
// base units and owns the cameras. Read-only over the engine.

Rectangle {
    id: board

    required property var engine
    required property real scaleX
    required property real scaleY
    required property color themeGreen
    required property color edgeColor
    required property var platColors
    required property color p1Color
    required property color p2Color
    required property real uiScale

    readonly property bool split: board.engine.p2Joined
    readonly property int panes: board.split ? 2 : 1
    readonly property real paneW: board.width / board.panes

    // one pane shows engine.viewportW world units: 440 solo, 220 split windowed,
    // 440 split fullscreen (two full-width panes side by side)
    width: engine.viewportW * board.panes * scaleX
    height: engine.baseH * scaleY
    color: Util.alpha(Color.background, 1.0)
    border.width: 1
    border.color: Util.alpha(Color.foreground, 0.25)
    radius: 6
    clip: true

    Repeater {
        model: board.panes
        delegate: BoardView {
            required property int index
            width: board.paneW
            height: board.height
            x: index * board.paneW
            engine: board.engine
            camX: index === 0 ? board.engine.camX1 : board.engine.camX2
            camY: index === 0 ? board.engine.camY1 : board.engine.camY2
            scaleX: board.scaleX
            scaleY: board.scaleY
            edgeColor: board.edgeColor
            platColors: board.platColors
            p1Color: board.p1Color
            p2Color: board.p2Color
            uiScale: board.uiScale
            selfIdx: index
        }
    }

    Rectangle {
        visible: board.split
        width: 2
        height: parent.height
        x: Math.round(board.width / 2) - 1
        color: Util.alpha(Color.foreground, 0.35)
        z: 3
    }

    // ---- overlays: idle ("pause") card + win card ----
    // laid out from their content; the text column is width-bounded so lines
    // wrap inside the border, and everything scales with the board
    readonly property real overlayScale: Math.max(0.6, board.scaleY)
    readonly property real overlayPad: Math.round(12 * board.overlayScale)
    // 0.6 em per character is the monospace advance the whole board is built on
    readonly property real overlayTextW: Math.max(160, board.width - 2 * board.overlayPad - 24)

    // idle overlay: ready card, shown whenever no round is running. Mode, who is
    // playing, the rule, then the controls as a grid; the prose is in the panel.
    Rectangle {
        id: idleCard
        anchors.centerIn: parent
        radius: 8
        z: 4
        visible: !board.engine.roundActive && board.engine.winner === ""
        color: Util.alpha(Color.background, 0.88)
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.3)
        width: idleCol.width + 2 * board.overlayPad
        height: idleCol.height + 2 * board.overlayPad

        Column {
            id: idleCol
            x: board.overlayPad
            y: board.overlayPad
            width: board.overlayTextW
            spacing: Math.round(4 * board.overlayScale)

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: board.engine.mode.name
                      + "  ·  " + (board.engine.p2Joined ? "split screen" : "solo")
                color: board.themeGreen
                font.family: "monospace"
                font.pixelSize: 14 * board.overlayScale
                font.bold: true
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: board.engine.mode.tagline
                color: Color.foreground
                font.family: "monospace"
                font.pixelSize: 11 * board.overlayScale
            }

            // thin rule between the tagline and the control list
            Rectangle {
                width: parent.width
                height: 1
                color: Util.alpha(Color.foreground, 0.22)
            }

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 2
                columnSpacing: Math.round(10 * board.overlayScale)
                rowSpacing: Math.round(2 * board.overlayScale)

                Text {
                    textFormat: Text.PlainText
                    text: "start"
                    color: board.themeGreen
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                    font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: "R or Enter  ·  pad Start"
                    color: Util.alpha(Color.foreground, 0.9)
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                }
                Text {
                    textFormat: Text.PlainText
                    // same words as the panel's button, so card and button row agree
                    text: board.engine.p2Joined ? "solo" : "split screen"
                    color: board.themeGreen
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                    font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: board.engine.p2Joined ? "J" : "J  ·  P2 joins"
                    color: Util.alpha(Color.foreground, 0.9)
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                }
                Text {
                    textFormat: Text.PlainText
                    text: "more"
                    color: board.themeGreen
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                    font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: "M modes  ·  F fullscreen"
                    color: Util.alpha(Color.foreground, 0.9)
                    font.family: "monospace"
                    font.pixelSize: 10 * board.overlayScale
                }
            }
        }
    }

    // ---- pause overlay ----
    //
    // same card treatment as the other overlays; the engine stops stepping while
    // paused, so the arena behind keeps its last frame, rocks included
    Rectangle {
        id: pauseCard
        anchors.centerIn: parent
        radius: 8
        z: 4
        visible: board.engine.paused && board.engine.roundActive
        color: Util.alpha(Color.background, 0.88)
        border.width: 1
        border.color: Util.alpha(board.themeGreen, 0.55)
        width: pauseCol.width + 2 * board.overlayPad
        height: pauseCol.height + 2 * board.overlayPad

        Column {
            id: pauseCol
            x: board.overlayPad
            y: board.overlayPad
            width: board.overlayTextW
            spacing: Math.round(4 * board.overlayScale)

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "❚❚  paused"
                color: board.themeGreen
                font.family: "monospace"
                font.pixelSize: 15 * board.overlayScale
                font.bold: true
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "clock stopped at " + board.engine.fmtTime(board.engine.elapsed)
                      + (board.engine.p2Joined ? "  ·  both players held" : "")
                color: Util.alpha(Color.foreground, 0.9)
                font.family: "monospace"
                font.pixelSize: 11 * board.overlayScale
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "P  ·  resume    Esc  ·  close the panel"
                color: Util.alpha(Color.foreground, 0.75)
                font.family: "monospace"
                font.pixelSize: 10 * board.overlayScale
            }
        }
    }

    // ---- win overlay ----
    // Shown 2 s after the win, so the glyph beat and the confetti land on the
    // frozen arena first. The engine already ended the run at the touch.
    property bool verdictOn: false
    Timer {
        id: verdictDelay
        interval: 2000
        onTriggered: board.verdictOn = true
    }
    Connections {
        target: board.engine
        function onRoundEnded(playerIdx, timeSec) { verdictDelay.restart() }
        function onRoundStarted() { verdictDelay.stop(); board.verdictOn = false }
    }

    Rectangle {
        id: winCard
        anchors.centerIn: parent
        radius: 8
        z: 4
        visible: board.verdictOn && board.engine.winner !== ""
        color: Util.alpha(Color.background, 0.92)
        border.width: 1
        border.color: board.themeGreen
        width: winCol.width + 2 * board.overlayPad
        height: winCol.height + 2 * board.overlayPad

        Column {
            id: winCol
            x: board.overlayPad
            y: board.overlayPad
            width: board.overlayTextW
            spacing: Math.round(4 * board.overlayScale)

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                // block-element stripe, not a flag emoji: the overlays are set in
                // the board's monospace art font, and ▀▄ is the finish line's
                // own pattern
                text: "▀▄▀▄  " + board.engine.winner + " wins"
                color: board.themeGreen
                font.family: "monospace"
                font.pixelSize: 15 * board.overlayScale
                font.bold: true
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: board.engine.fmtTime(board.engine.winTime)
                      + "  ·  falls 0:" + board.engine.falls1
                      + (board.engine.p2Joined ? " 2:" + board.engine.falls2 : "")
                color: Util.alpha(Color.foreground, 0.9)
                font.family: "monospace"
                font.pixelSize: 11 * board.overlayScale
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "R  ·  rematch    M  ·  modes"
                color: Util.alpha(Color.foreground, 0.75)
                font.family: "monospace"
                font.pixelSize: 10 * board.overlayScale
            }
        }
    }
}
