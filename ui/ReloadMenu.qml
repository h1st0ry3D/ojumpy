import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Right-click menu on the bar icon: asks the shell to rescan plugins.
//
// The open flag lives in the panel (`openState`, so bar clicks can toggle it);
// the component reports back through `dismissed()` when the popup hides itself, and
// `reloadRequested()` when the user picks the reload item.
PopupCard {
    id: reloadMenu

    required property var panel       // Panel root (bar, owner, theme colour)
    required property var anchorButton
    required property bool openState

    signal dismissed()          // the popup hid itself (name avoids PopupCard's own signal)
    signal reloadRequested()

    anchorItem: anchorButton
    owner: panel
    bar: panel.bar
    open: reloadMenu.openState
    triggerMode: "click"
    padding: Style.space(8)
    borderColor: panel.themeGreen
    contentWidth: reloadMenu.fittedContentWidth(Style.space(220))
    contentHeight: reloadMenu.fittedContentHeight(110, Style.space(160))
    onVisibleChanged: if (!visible) reloadMenu.dismissed()

    Column {
        anchors.fill: parent
        spacing: Style.space(2)

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: "Ojumpy  •  menu"
            color: Color.accent
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: true
            padding: Style.space(2)
        }

        Button {
            anchors.left: parent.left
            width: parent.width - Style.space(4)
            text: "\u21bb Reload plugin"
            onClicked: reloadMenu.reloadRequested()
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            width: parent.width
            wrapMode: Text.WordWrap
            text: "runs `omarchy-shell shell rescanPlugins`"
            color: Util.alpha(Color.foreground, 0.7)
            font.family: "monospace"
            font.pixelSize: 9
            padding: Style.space(2)
        }
    }
}
