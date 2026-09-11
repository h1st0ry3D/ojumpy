import QtQuick

// Landing ripple — the wave that starts where a glyph touches down and runs
// outwards over the platform art under it: a disc easing out, with a brighter
// ring riding its front, fading while it expands.
//
// The platform is text art, so there is no surface to tint: the wave lights the
// platform's *own* characters. Each cell carries an aligned overlay coloured
// with the platform ink mixed towards a lifted version of that ink, by the wave
// alpha at the cell centre — the cell the front is on flashes, washed cells
// settle to a soft glow, and nothing is added to the platform. Ripples come from
// a fixed pool of fixed cell grids, so a landing only changes bindings and never
// creates or destroys items.
Item {
    id: pool

    // Horizontal stretch of the world art (BoardView's `stretchX`): platform
    // characters are stretched by it, so the wave has to be too.
    property real stretchX: 1
    // Camera + scale of the pane this pool draws in. A ripple belongs to the
    // *platform*, not to the pane: it is placed at fire time and the pane then
    // pans under it, so each slot keeps its pane position together with the
    // camera of that moment and re-derives where it sits from the camera now.
    property real camX: 0
    property real camY: 0
    property real scaleX: 1
    property real scaleY: 1
    // How many landings can ripple at once; once all slots are busy the oldest
    // one is recycled.
    property int slots: 4
    property real duration: 500

    // The widest art the planner emits is the 13-char start pad; the finish band
    // is 12 chars over 2 rows. The per-slot cell grid is sized 14 x 2 to cover
    // anything, and shorter arts simply leave the extra cells empty.
    readonly property int maxRowChars: 14
    readonly property int maxRows: 2
    readonly property int cellCount: pool.maxRowChars * pool.maxRows

    // ---- wave ink ----
    // The platform colour with a raised HSV value: that is what makes the wave
    // read as light *on* the platform instead of a second colour on top of it.
    property real inkLift: 0.45
    // Front softness in character cells — the ring is ~2.5 of these wide, so
    // about 1.5 characters of the art glow at any moment.
    property real frontSoftness: 0.6
    // Peak alpha behind the front / on the front ring — the crest is meant to
    // reach the ripple ink, the wash behind it stays soft.
    property real discAlpha: 0.6
    property real ringAlpha: 0.8
    // Cells dimmer than this are not drawn at all.
    property real minAlpha: 0.012

    function liftedInk(ink) {
        var v = ink.hsvValue;
        var col = Qt.hsva(ink.hsvHue, Math.max(0.0, ink.hsvSaturation * 0.85),
                          Math.min(1.0, v + pool.inkLift), 1.0);
        // A colour already at full value cannot be lifted any further *as value*
        // — and the start pad and the finish band are exactly that: they are
        // painted in the theme's foreground, the inverse of the background. That
        // is what made the wave invisible on those two platforms while it worked
        // on every other one. Spend the leftover lift on mixing towards white
        // instead, i.e. carry on brightening; for the other platforms the spill
        // is zero and nothing changes.
        var spill = Math.min(1.0, Math.max(0.0, (v + pool.inkLift) - 1.0) / pool.inkLift);
        if (spill > 0) {
            var t = spill * 0.75;
            col = Qt.rgba(col.r + (1.0 - col.r) * t, col.g + (1.0 - col.g) * t,
                          col.b + (1.0 - col.b) * t, 1.0);
        }
        return col;
    }
    function mixInk(from, to, t) {
        return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t,
                       from.b + (to.b - from.b) * t, 1.0)
    }
    function smoothstep(edge0, edge1, x) {
        var t = Math.max(0.0, Math.min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    // ---- firing ----
    // impact({ paneX, artTopY, impactX, rows, px, cellAdvance, inkTop, rowH,
    //          rowAdvance, bold, ink })
    // everything in pane pixels: paneX/artTopY = the art's left edge / line-box
    // top, impactX = where the glyph landed, rows = the platform art (one string
    // per line), px = glyph font size, cellAdvance = advance of one character, in
    // font-size units (0.6 em — the monospace advance the engine sizes every
    // platform with), inkTop/rowH = painted top/height of one row inside the line
    // box, rowAdvance = line advance, ink = platform colour.
    property int cursor: 0
    function impact(a) {
        var n = pool.slots
        var slot = null
        for (var i = 0; i < n; i++) {          // prefer a free slot
            var s = poolRepeater.itemAt((pool.cursor + i) % n)
            if (s && !s.running) {
                slot = s
                pool.cursor = (pool.cursor + i + 1) % n
                break
            }
        }
        if (!slot) {                           // all busy: recycle the oldest
            slot = poolRepeater.itemAt(pool.cursor % n)
            pool.cursor = (pool.cursor + 1) % n
        }
        if (slot) slot.fire(a)
    }

    Repeater {
        id: poolRepeater
        model: pool.slots

        delegate: Item {
            id: ripple
            required property int index

            // set by fire()
            property bool running: false
            property real progress: 0
            property real maxRadius: 1
            property real soft: 6
            property real cellW: 9
            property real rowAdvance: 17
            property real rowH: 11
            property real impactX: 0
            property real impactY: 0
            // pane position at fire time + the camera it was measured against
            property real anchorX: 0
            property real anchorY: 0
            property real anchorCamX: 0
            property real anchorCamY: 0
            property real fontSize: 15
            property bool bold: true
            property color ink: "white"
            property color brightInk: "white"
            property var cells: []

            visible: ripple.running
            // ride the camera: the platform scrolls with it, the wave rides along
            x: ripple.anchorX + (ripple.anchorCamX - pool.camX) * pool.scaleX
            y: ripple.anchorY + (ripple.anchorCamY - pool.camY) * pool.scaleY
            // Wave front: the reference shader's ease-out expansion (fast start,
            // soft settle), plus the fade that takes over once the wave is well
            // away from the impact.
            readonly property real front: (1 - (1 - progress) * (1 - progress)) * ripple.maxRadius
            readonly property real fade: 1 - pool.smoothstep(0.35, 1.0, ripple.progress)

            // Wave alpha at a distance from the impact: filled disc plus the
            // brighter ring riding its front (the water-drop highlight).
            function alphaAt(distance) {
                var r = ripple.front
                var s = ripple.soft
                var disc = 1 - pool.smoothstep(r - s, r, distance)
                var ring = pool.smoothstep(r - s * 2.5, r - s * 0.5, distance)
                         * (1 - pool.smoothstep(r - s * 0.5, r + s * 0.5, distance))
                var body = disc * pool.discAlpha + ring * pool.ringAlpha
                return Math.max(0.0, Math.min(1.0, body * ripple.fade))
            }

            function fire(a) {
                var rows = a.rows || []
                ripple.cellW = Math.max(1, (a.cellAdvance || 0.6) * a.px * pool.stretchX)
                ripple.rowAdvance = Math.max(1, a.rowAdvance)
                ripple.rowH = Math.max(1, a.rowH)
                ripple.fontSize = a.px
                ripple.bold = a.bold !== false
                ripple.ink = a.ink
                // read the colour property back: an ink given as a string still
                // converts here, so the lift works on a real colour either way
                ripple.brightInk = pool.liftedInk(ripple.ink)
                ripple.anchorX = a.paneX
                ripple.anchorY = a.artTopY
                ripple.anchorCamX = pool.camX
                ripple.anchorCamY = pool.camY
                // the wave starts on the platform's painted top line, right
                // under the feet, and grows from there
                ripple.impactX = a.impactX - a.paneX
                ripple.impactY = a.inkTop
                ripple.soft = Math.max(1.5, ripple.cellW * pool.frontSoftness)

                var list = []
                var widest = 0
                var last = rows.length
                for (var r = 0; r < last; r++) {
                    var line = String(rows[r])
                    widest = Math.max(widest, line.length)
                    // centre of this row's painted band, measured from the ink
                    // top that the platform delegate aligns its own art on
                    var cy = a.inkTop + r * ripple.rowAdvance + ripple.rowH * 0.5
                    for (var c = 0; c < line.length; c++) {
                        var cx = (c + 0.5) * ripple.cellW
                        list.push({ ch: line.charAt(c), x: c * ripple.cellW,
                                    y: r * ripple.rowAdvance,
                                    dist: Math.hypot(cx - ripple.impactX, cy - ripple.impactY) })
                    }
                }
                ripple.cells = list
                ripple.width = widest * ripple.cellW
                ripple.height = last * ripple.rowAdvance

                // far enough to wash over the whole art from any impact point
                var far = 0
                var xs = [0, ripple.width]
                var ys = [0, ripple.height]
                for (var i = 0; i < 2; i++) {
                    for (var j = 0; j < 2; j++) {
                        far = Math.max(far, Math.hypot(xs[i] - ripple.impactX,
                                                       ys[j] - ripple.impactY))
                    }
                }
                ripple.maxRadius = Math.max(1, far * 1.05)

                ripple.progress = 0
                ripple.running = true
                runAnim.restart()
            }

            SequentialAnimation {
                id: runAnim
                PropertyAnimation {
                    target: ripple
                    property: "progress"
                    from: 0; to: 1
                    duration: pool.duration
                    easing.type: Easing.Linear   // the wave math eases the radius itself
                }
                ScriptAction { script: ripple.running = false }
            }

            // One aligned overlay character per cell of the art.
            Repeater {
                model: pool.cellCount
                delegate: Text {
                    textFormat: Text.PlainText
                    required property int index
                    readonly property var cell: ripple.cells[index]
                    readonly property real wave: (ripple.running && cell)
                                                  ? ripple.alphaAt(cell.dist) : 0
                    visible: ripple.running && wave > pool.minAlpha
                    x: cell ? cell.x : 0
                    y: cell ? cell.y : 0
                    text: cell ? cell.ch : ""
                    color: pool.mixInk(ripple.ink, ripple.brightInk, wave)
                    font.family: "monospace"
                    font.pixelSize: ripple.fontSize
                    font.bold: ripple.bold
                    transform: Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: pool.stretchX
                    }
                }
            }
        }
    }
}
