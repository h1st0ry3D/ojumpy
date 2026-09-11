import QtQuick
import "../core/GameModes.js" as Modes
import "Plain.js" as Plain
import qs.Commons
import qs.Ui

// Ojumpy mode selection overlay. Lists GameModes.js entries; ready modes are
// pickable (click or 1..9 while open), scaffolded modes show as "soon".
// Emits picked(modeId); the panel applies it and returns to the game view.

Rectangle {
    id: modeSelect

    required property var engine
    required property real uiScale
    required property color themeGreen

    signal picked(string modeId)

    readonly property var modeList: Modes.list()

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
                opacity: modelData.ready ? 1.0 : 0.55
                onClicked: modeSelect.pick(modelData)
            }
        }

        Item { height: 1; width: 1 }

        Text {
            textFormat: Text.PlainText
            text: "Esc closes • 1..3 picks • race-style: J joins P2 (split screen, own camera)"
            color: Util.alpha(Color.foreground, 0.7)
            font.family: "monospace"
            font.pixelSize: 10 * modeSelect.uiScale
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}
