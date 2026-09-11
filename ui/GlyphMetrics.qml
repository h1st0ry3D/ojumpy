import QtQuick

// Ink geometry of the board's text art.
//
// Every character paints at a different height inside its line box ("////" is
// tall, "----" is a thin mid line, "____" hugs the baseline). The collision top
// must match the *painted* top so a player stands on the art, and the player
// glyph must rest its painted bottom on that same line — for any character.
//
// Bounds are measured once at pixelSize 100 and scaled by font size: linear, and
// no probe mutation during delegate bindings.
//
// Art must stay a plain 0.6 em character grid (the engine sizes collision boxes
// from it), so the font's contextual alternates are off here *and* on the art —
// JetBrains Mono would otherwise ligate "<<<"/">>>" runs into tightened glyphs
// that no longer sit on the grid. What is measured is what is painted.
//
// Root is a zero-sized Item because QtObject has no default property for the
// probe children.
Item {
    id: metrics
    width: 0
    height: 0

    // Art to measure: every platform pattern (the finish band included) and every
    // player glyph. Multi-row art is measured per row as well, because the ripple
    // overlays one row at a time.
    property var platformGlyphs: []
    property var playerGlyphs: []
    property var hazardGlyphs: []
    property var orbGlyphs: []

    readonly property var artFontFeatures: ({ "liga": 0, "calt": 0, "clig": 0 })

    TextMetrics {
        id: glyphProbe
        font.family: "monospace"
        font.pixelSize: 100
        font.features: metrics.artFontFeatures
        text: "0"
    }
    TextMetrics {
        id: digitProbe
        font.family: "monospace"
        font.pixelSize: 100
        text: "O"
    }
    TextMetrics {
        id: lineProbe          // one line vs two: art line advance (finish band)
        font.family: "monospace"
        font.pixelSize: 100
        text: "0"
    }

    property real baseline100: 100             // font ascent at pixelSize 100
    property var platformInkTopRatio: ({})     // glyph -> ink top / font px
    property var platformInkHeightRatio: ({})  // glyph / row -> painted height / font px
    property real rowAdvanceRatio: 1.0         // art line advance / font px
    property var playerInkBottomRatio: ({})    // player glyph -> ink bottom / font px
    property var playerInkHeightRatio: ({})    // player glyph -> painted height / font px
    // hazard glyphs (Asterisk Attack's rocks): the mode's size classes are ink
    // *widths*, so the horizontal numbers are measured too — the view then
    // places the ink box exactly where the engine simulates it
    property var hazardInkLeftRatio: ({})      // glyph -> pen origin -> ink left / font px
    property var hazardInkWidthRatio: ({})     // glyph -> ink width / font px
    property var hazardInkCenterRatio: ({})    // glyph -> box top -> ink v-centre / font px
    // the finish orb: sized by its ink *height* (the engine fixes the painted
    // radius, so the font follows from the circle's measured height), and
    // centred through the same ink box the collision uses
    property var orbInkLeftRatio: ({})         // glyph -> pen origin -> ink left / font px
    property var orbInkWidthRatio: ({})        // glyph -> ink width / font px
    property var orbInkHeightRatio: ({})       // glyph -> ink height / font px
    property var orbInkCenterRatio: ({})       // glyph -> box top -> ink v-centre / font px

    // Distance from the text box top down to the painted top of a glyph.
    function inkTopPx(glyph, pixelSize) {
        return (metrics.platformInkTopRatio[glyph] || 0) * pixelSize;
    }

    // Painted height of a glyph / art row (the landing ripple's wave centre).
    function inkHeightPx(glyph, pixelSize) {
        return (metrics.platformInkHeightRatio[glyph] || 0.7) * pixelSize;
    }

    // Distance from the text box top down to a player glyph's painted bottom.
    function playerInkBottomPx(glyph, pixelSize) {
        return (metrics.playerInkBottomRatio[glyph] || 1.0) * pixelSize;
    }

    // Painted height of a player glyph (a glider's hat included).
    function playerInkHeightPx(glyph, pixelSize) {
        return (metrics.playerInkHeightRatio[glyph] || 0.75) * pixelSize;
    }

    // Hazard glyph ink box: left edge (from the text's pen origin), width, and
    // the vertical centre (from the box top). A rock is drawn at the size the
    // engine collides with by sizing the font from the width.
    function hazardInkLeftPx(glyph, pixelSize) {
        return (metrics.hazardInkLeftRatio[glyph] || 0) * pixelSize;
    }
    function hazardInkWidthPx(glyph, pixelSize) {
        return (metrics.hazardInkWidthRatio[glyph] || 0.6) * pixelSize;
    }
    function hazardInkCenterPx(glyph, pixelSize) {
        return (metrics.hazardInkCenterRatio[glyph] || 0.75) * pixelSize;
    }

    // Finish orb ink box, same shape as the hazard helpers. The painted
    // diameter is 2 * engine.orbR, so the font size comes from the height ratio
    // and everything else follows from the measured box.
    function orbInkLeftPx(glyph, pixelSize) {
        return (metrics.orbInkLeftRatio[glyph] || 0) * pixelSize;
    }
    function orbInkWidthPx(glyph, pixelSize) {
        return (metrics.orbInkWidthRatio[glyph] || 1.0) * pixelSize;
    }
    function orbInkHeightPx(glyph, pixelSize) {
        return (metrics.orbInkHeightRatio[glyph] || 0.7) * pixelSize;
    }
    function orbInkCenterPx(glyph, pixelSize) {
        return (metrics.orbInkCenterRatio[glyph] || 0.75) * pixelSize;
    }

    function measure() {
        metrics.baseline100 = -glyphProbe.boundingRect.y;

        var tops = {};
        var heights = {};
        var arts = (metrics.platformGlyphs || []).slice();
        for (var i = 0; i < arts.length; i++) {
            // whole art (platform placement) and, for multi-row art, every row
            // on its own — the landing ripple overlays one row at a time
            var keys = [arts[i]];
            var rows = String(arts[i]).split("\n");
            if (rows.length > 1) keys = keys.concat(rows);
            for (var k = 0; k < keys.length; k++) {
                glyphProbe.text = keys[k];
                var bounds = glyphProbe.tightBoundingRect;
                tops[keys[k]] = (metrics.baseline100 + bounds.y) / 100;
                heights[keys[k]] = bounds.height / 100;
            }
        }
        metrics.platformInkTopRatio = tops;
        metrics.platformInkHeightRatio = heights;

        // art line advance: the second line of a two-line probe sits this far
        // below the first (same font as the art, which draws at lineHeight 1.0)
        lineProbe.text = "0";
        var oneLine = lineProbe.height;
        lineProbe.text = "0\n0";
        metrics.rowAdvanceRatio = Math.max(0.8, (lineProbe.height - oneLine) / 100);

        // player glyphs: the glider (Ô) carries its hat above the O, so its
        // painted bottom is unchanged — measured anyway, per glyph
        var bottoms = {};
        var pHeights = {};
        var players = metrics.playerGlyphs || [];
        for (var j = 0; j < players.length; j++) {
            digitProbe.text = players[j];
            var ptr = digitProbe.tightBoundingRect;
            bottoms[players[j]] = (metrics.baseline100 + ptr.y + ptr.height) / 100;
            pHeights[players[j]] = ptr.height / 100;
        }
        metrics.playerInkBottomRatio = bottoms;
        metrics.playerInkHeightRatio = pHeights;

        // hazard glyphs: the asterisk sizes are ink widths, so measure the
        // horizontal extents (and the ink centre) as well
        var haz = metrics.hazardGlyphs || [];
        var hLeft = {}, hWidth = {}, hCenter = {};
        for (var h = 0; h < haz.length; h++) {
            digitProbe.text = haz[h];
            var hb = digitProbe.tightBoundingRect;
            hLeft[haz[h]] = hb.x / 100;
            hWidth[haz[h]] = hb.width / 100;
            hCenter[haz[h]] = (metrics.baseline100 + hb.y + hb.height / 2) / 100;
        }
        metrics.hazardInkLeftRatio = hLeft;
        metrics.hazardInkWidthRatio = hWidth;
        metrics.hazardInkCenterRatio = hCenter;

        // finish orb glyph: full ink box, height included (the orb's font size
        // is derived from the painted diameter)
        var orbs = metrics.orbGlyphs || [];
        var oLeft = {}, oWidth = {}, oHeight = {}, oCenter = {};
        for (var o = 0; o < orbs.length; o++) {
            digitProbe.text = orbs[o];
            var ob = digitProbe.tightBoundingRect;
            oLeft[orbs[o]] = ob.x / 100;
            oWidth[orbs[o]] = ob.width / 100;
            oHeight[orbs[o]] = ob.height / 100;
            oCenter[orbs[o]] = (metrics.baseline100 + ob.y + ob.height / 2) / 100;
        }
        metrics.orbInkLeftRatio = oLeft;
        metrics.orbInkWidthRatio = oWidth;
        metrics.orbInkHeightRatio = oHeight;
        metrics.orbInkCenterRatio = oCenter;
    }

    onPlatformGlyphsChanged: metrics.measure()
    onPlayerGlyphsChanged: metrics.measure()
    onHazardGlyphsChanged: metrics.measure()
    onOrbGlyphsChanged: metrics.measure()
    Component.onCompleted: metrics.measure()
}
