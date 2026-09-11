import QtQuick
import qs.Commons
import qs.Ui

// The bar icon.
//
// BarIconButton draws a fixed icon slot and hides its text, so the live label
// ("99_100") has to size the slot itself: measure it at the bar font, add a
// little breathing room, never go below the standard slot.
//
// Left click toggles the panel; a right click only reports up (`reloadRequested`)
// — the open flag belongs to the panel so bar clicks can toggle it.
BarIconButton {
    id: barButton

    required property var game        // GameEngine
    required property var panel       // Panel root (bar, pad state, toggle)
    required property string label    // live label, e.g. "99_100" or "Ö_Ö"

    signal reloadRequested()

    readonly property real labelPadX: Style.spaceReal(4)
    readonly property real slotW: Math.max(Style.bar.iconSlot,
        Math.ceil(labelMetrics.width) + 2 * barButton.labelPadX)

    TextMetrics {
        id: labelMetrics
        font.family: barButton.fontFamily
        font.pixelSize: Math.round(barButton.fontSize)
        text: barButton.label
    }

    anchors.fill: parent
    bar: barButton.panel.bar
    text: barButton.label
    slotSize: barButton.slotW
    onPressed: function(btn) {
        if (btn === Qt.RightButton) barButton.reloadRequested();
        else barButton.panel.toggle();
    }
}
