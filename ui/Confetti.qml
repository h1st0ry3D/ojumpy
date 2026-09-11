import QtQuick

// The win shower: character bits fall from the top of whatever this fills and
// fade around the middle. Decorative only — the animation runs while `running`,
// and each bit's path comes from cheap hashes of its index, so no state and no
// random source are needed.
Item {
    id: confetti

    property string chars: "*+#%;:`´~"
    property var palette: []          // colours to cycle through
    property real scale: 1.0          // uiScale
    property bool running: false      // animation runs only while true

    visible: running
    clip: true

    readonly property real fallTo: height * 0.5

    Repeater {
        model: 64
        delegate: Text {
            textFormat: Text.PlainText
            id: bit

            required property int index
            readonly property real r1: ((index * 9301 + 49297) % 233280) / 233280
            readonly property real r2: (((index + 7) * 4703 + 7919) % 199999) / 199999
            readonly property real r3: (((index + 13) * 2711 + 104729) % 150001) / 150001
            readonly property int delay: Math.round(r2 * 900)
            readonly property int dur: Math.round(1100 + r3 * 1500)
            readonly property real drift: (r1 - 0.5) * 90

            text: confetti.chars.charAt(index % confetti.chars.length)
            color: confetti.palette.length > 0
                   ? confetti.palette[index % confetti.palette.length] : "transparent"
            font.family: "monospace"
            font.pixelSize: Math.round((13 + r3 * 12) * confetti.scale)
            font.bold: true
            opacity: 0
            rotation: r3 * 360

            SequentialAnimation {
                loops: Animation.Infinite
                running: confetti.running
                PropertyAnimation { target: bit; property: "y"; to: -30; duration: 0 }
                PropertyAnimation { target: bit; property: "opacity"; to: 0; duration: 0 }
                PropertyAnimation { target: bit; property: "x"
                                    to: Math.round(bit.r1 * confetti.width); duration: 0 }
                PauseAnimation { duration: bit.delay }
                ParallelAnimation {
                    PropertyAnimation {
                        target: bit; property: "y"
                        from: -30; to: confetti.fallTo; duration: bit.dur
                        easing.type: Easing.InQuad
                    }
                    PropertyAnimation {
                        target: bit; property: "x"
                        from: Math.round(bit.r1 * confetti.width)
                        to: Math.round(bit.r1 * confetti.width + bit.drift)
                        duration: bit.dur
                    }
                    SequentialAnimation {
                        PropertyAnimation {
                            target: bit; property: "opacity"
                            from: 0; to: 0.9; duration: Math.round(bit.dur * 0.45)
                        }
                        PropertyAnimation {
                            target: bit; property: "opacity"
                            to: 0; duration: bit.dur - Math.round(bit.dur * 0.45)
                        }
                    }
                    PropertyAnimation {
                        target: bit; property: "rotation"
                        from: 0; to: 360; duration: Math.max(200, Math.round(bit.dur * 0.7))
                    }
                }
            }
        }
    }
}
