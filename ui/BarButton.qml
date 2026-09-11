import QtQuick
import qs.Commons
import qs.Ui
import "Plain.js" as Plain

// The bar icon.
//
// BarIconButton draws a fixed icon slot and hides its text, so the live label
// ("99_100") has to size the slot itself: measure it at the bar font, add a
// little breathing room, never go below the standard slot. That is also why the
// label must not change for anything transient — a different length moves the
// slot, and the panel is anchored to this button, so the whole panel would
// shift. The paused state therefore lives in the tooltip, not in the label.
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

    // Host-rendered tooltip: the words are ours, the sink is the shell's, so the
    // line is flattened and capped first (ui/Plain.js). It is where the transient
    // state goes — running/paused, and whether a pad is feeding the game.
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
