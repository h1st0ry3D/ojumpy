import QtQuick
import "../core/GameModes.js" as Modes
import "Plain.js" as Plain
import qs.Commons
import qs.Ui

// Ojumpy mode selection overlay. Lists GameModes.js entries; ready modes are
// pickable (click, 1..9, or the cursor: up/down moves it, Enter/A picks).
// Emits picked(modeId); the panel applies it and returns to the game view.

Rectangle {
    id: modeSelect

    required property var engine
    required property real uiScale
    required property color themeGreen

    signal picked(string modeId)

    readonly property var modeList: Modes.list()

    // Highlight row. Moved by a click's hover, the keyboard (Panel's key
    // handler), or a pad (Panel's tick); all three go through the functions
    // below, so the picker itself never has to know which one asked.
    property int cursorIndex: 0

    color: Util.alpha(Color.background, 0.96)
    border.width: 1
    border.color: modeSelect.themeGreen
    radius: 8
    clip: true

    function pick(m) {
        if (!m || m.ready !== true) return;
        if (m.id === modeSelect.engine.modeId) {
            modeSelect.picked(m.id);
            return;
        }
        modeSelect.engine.modeId = m.id;
        modeSelect.picked(m.id);
    }

    // Land on the mode that is playing, so the cursor starts where the user is.
    function syncCursor() {
        var list = modeSelect.modeList;
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === modeSelect.engine.modeId) { modeSelect.cursorIndex = i; return; }
        }
        modeSelect.cursorIndex = 0;
    }

    // Step to the next *ready* mode, wrapping. Scaffolded entries are shown but
    // skipped: a cursor that cannot be acted on is just a dead stop.
    function moveCursor(delta) {
        var list = modeSelect.modeList;
        var n = list.length;
        if (n === 0) return;
        var i = modeSelect.cursorIndex;
        for (var step = 0; step < n; ++step) {
            i = ((i + delta) % n + n) % n;
            if (list[i].ready === true) { modeSelect.cursorIndex = i; return; }
        }
    }

    function activateCursor() {
        modeSelect.pick(modeSelect.modeList[modeSelect.cursorIndex]);
    }

    // The cursor follows the mouse too, so hover and keys never disagree.
    onVisibleChanged: if (visible) modeSelect.syncCursor()

    Column {
        anchors.fill: parent
        anchors.margins: 14 * modeSelect.uiScale
        spacing: 8 * modeSelect.uiScale

        Text {
            textFormat: Text.PlainText
            text: "Ojumpy — pick a mode"
            color: modeSelect.themeGreen
            font.family: "monospace"
            font.pixelSize: 16 * modeSelect.uiScale
            font.bold: true
        }

        Repeater {
            model: modeSelect.modeList
            delegate: Button {
                required property var modelData
                required property int index
                // the list shows mode names only: the number key that picks a
                // mode is a shortcut, so it lives in the tooltip
                width: parent.width
                text: modelData.name
                      + (modelData.id === modeSelect.engine.modeId ? "   (current)" : "")
                      + (modelData.ready ? "" : "   ·   soon")
                // host-rendered tooltip: mode names are ours but the sink is
                // the shell's, so they are flattened and capped first
                tooltipText: Plain.plain(modelData.ready
                    ? "Pick " + modelData.name + " (key " + (index + 1) + ")"
                    : modelData.name + " is not ready yet")
                fontSize: 12 * modeSelect.uiScale
                bordered: modelData.id === modeSelect.engine.modeId
                selected: modelData.id === modeSelect.engine.modeId
                // the shell's own cursor paint (same flag ButtonGroup drives)
                hasCursor: modeSelect.cursorIndex === index
                onHovered: function(h) { if (h) modeSelect.cursorIndex = index }
                opacity: modelData.ready ? 1.0 : 0.55
                onClicked: modeSelect.pick(modelData)
            }
        }

        Item { height: 1; width: 1 }

        Text {
            textFormat: Text.PlainText
            text: "Esc closes • ↑/↓ then Enter picks • keys 1..3 pick • pad: ↑/↓ + A (Select closes)"
                      + " • race-style: J joins P2 (split screen, own camera)"
            color: Util.alpha(Color.foreground, 0.7)
            font.family: "monospace"
            font.pixelSize: 10 * modeSelect.uiScale
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}
