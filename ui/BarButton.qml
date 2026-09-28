import QtQuick
import qs.Commons
import qs.Ui
import "Plain.js" as Plain

// The bar icon.
//
// BarIconButton draws a fixed icon slot and hides its text, so the live label
// ("99_100") has to size the slot: measured at the bar font plus a little
// padding, never below the standard slot. The label must therefore not change
// for anything transient: a different length moves the slot, and the panel is
// anchored to this button. Transient state lives in the tooltip instead.
//
// Left click toggles the panel; a right click only reports up.
BarIconButton {
    id: barButton

    required property var game        // GameEngine
    required property var panel       // Panel root (bar, pad state, toggle)
    required property string label    // live label, e.g. "99_100" or "Ö_Ö"

    signal reloadRequested()

    readonly property real labelPadX: Style.spaceReal(4)
    readonly property real slotW: Math.max(Style.bar.iconSlot,
        Math.ceil(labelMetrics.width) + 2 * barButton.labelPadX)

    // host-rendered, so the line is flattened and capped first (ui/Plain.js);
    // this is where the transient state goes: running/paused, pad or keyboard
    readonly property string statusLine: game.mode.name
        + (game.roundActive ? (game.paused ? " · paused" : " · running") : "")
        + " · " + (barButton.panel.pad && barButton.panel.pad.connected
                    ? "pad ×" + barButton.panel.pad.pads
                    : "keyboard")
    tooltipText: Plain.plain("Ojumpy — " + barButton.statusLine)

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
