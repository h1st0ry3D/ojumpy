import QtQuick
import qs.Commons

// Ojumpy viewport — one pane, one camera.
//
// The engine simulates in base units (440x500); a BoardView renders that world
// through one camera (camX/camY = world coords at the pane's top-left corner), so
// the pane shows view.width/scaleX by view.height/scaleY world units.
//
// Both glyphs render in every pane (P2 only once joined), so each player sees the
// other. A player outside the pane is pinned to the pane edge, dimmed and marked
// with a ▲▼◀▶ caret. Read-only over the engine: no game logic here.

Item {
    id: view

    required property var engine
    required property real camX       // world x at the pane's left edge
    required property real camY       // world y at the pane's top edge
    required property real scaleX
    required property real scaleY
    required property color edgeColor     // start pad + finish line
    required property var platColors      // [smallest, middle, longest]
    required property color p1Color
    required property color p2Color
    required property real uiScale
    required property int selfIdx     // pane owner: 0 = P1, 1 = P2

    // Match or Fall: a tagged platform wears player 1's or player 2's colour, and
    // a player wears the colour of their current form (form 0 = p1Color,
    // form 1 = p2Color). Outside that mode a player is always in their own
    // colour, so this is the identity mapping.
    function formColor(form) { return form === 1 ? view.p2Color : view.p1Color; }
    readonly property color selfColor: view.formColor(view.engine.mode.matchFall === true
                                     ? (view.selfIdx === 0 ? view.engine.p1Form
                                                           : view.engine.p2Form)
                                     : view.selfIdx)
    // start pad and finish line share one colour; the rest is graded by size, or
    // by form in Match or Fall
    function platColor(plat) {
        if (plat.idx === 0 || plat.idx === view.engine.platCount - 1) return view.edgeColor;
        if (plat.form !== undefined) return view.formColor(plat.form);
        return view.platColors[plat.sizeClass] || view.platColors[0];
    }
    readonly property bool isSelf: view.selfIdx === 0
    readonly property int selfPlat: view.isSelf ? view.engine.p1Plat : view.engine.p2Plat
    readonly property int selfFalls: view.isSelf ? view.engine.falls1 : view.engine.falls2

    // ---- glyph ink metrics ----
    // GlyphMetrics.qml owns the probes, the ink ratios and the lookup helpers.
    readonly property string playerGlyph: "Ö"
    readonly property string glideGlyph: "Ô"   // O with a circumflex: the glider
    readonly property string deathGlyph: "Ø"   // crossed O: a death marker
    // Landing impact: the glyph drops to the plain `o` for a moment, the same glyph
    // the idle blink closes into.
    readonly property string landingGlyph: "o"
    // Idle: after `idleSeconds` without moving, a small ö with blinking dots;
    // `blinkGlyph` is the plain o.
    readonly property string idleGlyph: "ö"
    readonly property string blinkGlyph: "o"
    readonly property real idleSeconds: 3
    readonly property int idleBlinks: 10
    // Every character the mode can drop, measured so a drop's ink box is its
    // collision box: the mode's size-class glyphs plus its fallback character, so
    // an out-of-range class still has metrics to draw with.
    readonly property var hazardGlyphs: view.hazardGlyphList()
    function hazardGlyphList() {
        var h = view.engine.mode.hazard;
        if (!h) return ["*"];
        var list = h.glyphs ? h.glyphs.slice(0) : [];
        if (h.glyph && list.indexOf(h.glyph) < 0) list.push(h.glyph);
        if (list.length === 0) list.push("*");
        return list;
    }
    // How far a footstep dips the player glyph: the walk wobble scales the glyph
    // down to this and springs it back, 80/120 ms.
    readonly property real stepSquash: 0.78


    GlyphMetrics {
        id: ink
        platformGlyphs: view.engine.glyphs.concat([view.engine.finishGlyph])
        playerGlyphs: [view.playerGlyph, view.glideGlyph, view.deathGlyph, view.landingGlyph,
                       view.idleGlyph, view.blinkGlyph]
        hazardGlyphs: view.hazardGlyphs
        orbGlyphs: [view.orbGlyph]
    }

    // Character advance of platform art in font-size units, the ripple grid's step.
    // 0.6 em is the monospace advance the engine sizes every platform with
    // (GameEngine.platCharW).
    readonly property real charAdvanceRatio: 0.6

    // Fullscreen can stretch the arena horizontally (scaleX != scaleY): collision
    // boxes use scaleX while glyphs are sized from scaleY, so art is stretched by
    // this to keep the painted platform as wide as its box. 1 in the normal view.
    readonly property real stretchX: view.scaleX / Math.max(0.0001, view.scaleY)

    readonly property real playerFontPx: 20 * view.scaleY

    // ---- finish orb ----
    readonly property string orbGlyph: "●"
    readonly property color orbDark: "#FF8C00"    // dark orange, at the low pulse
    readonly property color orbLight: "#FFFFE0"   // light yellow, at the high one
    // The engine owns the pulse, so the paint matches the hitbox.
    function orbRamp(t) {
        return Qt.rgba(view.orbDark.r + (view.orbLight.r - view.orbDark.r) * t,
                       view.orbDark.g + (view.orbLight.g - view.orbDark.g) * t,
                       view.orbDark.b + (view.orbLight.b - view.orbDark.b) * t, 1.0)
    }
    // the engine fixes the radius, so the font size follows the ink height
    readonly property real orbFontPx: 2 * view.engine.orbRNow
        / Math.max(0.3, ink.orbInkHeightRatio[view.orbGlyph] || 0.7) * view.scaleY
    // 1 -> 0 over the engine's 0.18 s shrink once the orb is taken
    property real orbScale: 1.0
    // set when the 180 ms shrink finishes, so the orb stays drawn through the take
    property bool orbGone: false
    readonly property bool orbVisible: !view.orbGone && view.engine.orbActive
        && (view.engine.roundActive || view.engine.orbTaken)

    NumberAnimation {
        id: orbShrink
        target: view
        property: "orbScale"
        from: 1.0
        to: 0.0
        duration: 180
        easing: Easing.InCubic
        onFinished: view.orbGone = true
    }
    Connections {
        target: view.engine
        function onOrbCollected(playerIdx) { orbShrink.restart() }
        function onRoundStarted() {
            orbShrink.stop()
            view.orbScale = 1.0
            view.orbGone = false
        }
    }

    // ---- bump glow ----
    // A hit mixes the glyph colour towards white for hitGlowSeconds and fades it
    // linearly. Only the colour changes: the glyph keeps its weight.
    readonly property real hitGlowSeconds: 0.35
    readonly property real hitGlowFill: 0.55    // mix towards white at full pulse
    // A correct Glyph Hunt catch flashes the other way: a shorter, brighter
    // pulse, and the glyph goes bold at the peak. Bigger than a bump's fill, so
    // "I scored" never reads as "I got shoved".
    readonly property real collectGlowSeconds: 0.3
    readonly property real collectGlowFill: 0.95
    function glowInk(base, pulse, amount) {
        if (pulse <= 0) return base;
        var t = amount * pulse;
        return Qt.rgba(base.r + (1.0 - base.r) * t,
                       base.g + (1.0 - base.g) * t,
                       base.b + (1.0 - base.b) * t, 1.0);
    }

    clip: true

    // ---- landing ripple ----
    // LandRipple.qml draws a wave that runs outwards over the platform's own
    // characters as an aligned per-character overlay, so the art never changes.
    // Fixed pool, no per-landing item creation.
    LandRipple {
        id: ripples
        z: 1.5          // above the platform art it lights up, below the players
        stretchX: view.stretchX
        camX: view.camX
        camY: view.camY
        scaleX: view.scaleX
        scaleY: view.scaleY
    }

    // The engine's landed() carries the platform's left edge, not the platform, so
    // the art (and the ink colour picked from it) is looked up by that edge.
    function platUnder(platX) {
        var list = view.engine.platforms;
        for (var i = 0; i < list.length; i++) {
            if (list[i].x === platX) return list[i];
        }
        return null;
    }

    function impact(wx, platX, platW, platTop, glyph) {
        var plat = view.platUnder(platX);
        if (!plat) return;
        var rows = String(glyph).split("\n");          // exactly what the platform draws
        var px = Math.max(9, Math.round(15 * view.scaleY));
        var bold = !!plat.edge;
        var boxW = platW * view.scaleX;
        var artW = rows[0].length * px * 0.6 * view.stretchX;   // planner width, as drawn
        var platTopPaneY = (platTop - view.camY) * view.scaleY;   // painted platform top
        ripples.impact({
            paneX: (platX - view.camX) * view.scaleX + (boxW - artW) / 2,
            artTopY: platTopPaneY - ink.inkTopPx(rows[0], px),
            impactX: (wx + view.engine.playerW / 2 - view.camX) * view.scaleX,
            rows: rows,
            px: px,
            cellAdvance: view.charAdvanceRatio,
            inkTop: ink.inkTopPx(rows[0], px),
            rowH: ink.inkHeightPx(rows[0], px),
            rowAdvance: px * ink.rowAdvanceRatio,
            bold: bold,
            ink: view.platColor(plat)
        });
    }

    Connections {
        target: view.engine
        function onLanded(playerIdx, x, platX, platW, platTop, glyph) {
            view.impact(x, platX, platW, platTop, glyph);
        }
    }

    // ---- platforms ----
    Repeater {
        model: view.engine.platforms
        delegate: Text {
            textFormat: Text.PlainText
            required property var modelData
            // Glyph size follows the vertical world metric (scaleY). The art is
            // drawn exactly as authored, one pattern per size, so the engine sizes
            // each platform to its own pattern width; the art is centred on the box
            // to absorb scaleX/scaleY rounding. Art may be multi-row (finish band).
            readonly property real glyphPx: Math.max(9, Math.round(15 * view.scaleY))
            readonly property var artRows: String(modelData.glyph).split("\n")
            readonly property real artW: artRows[0].length * glyphPx * 0.6 * view.stretchX
            readonly property real boxW: modelData.w * view.scaleX
            readonly property real sx: (modelData.x - view.camX) * view.scaleX
            readonly property real sy: (modelData.y - view.camY) * view.scaleY
            // camera culling: only render platforms inside the view
            visible: sy > -30 && sy < view.height + 30
                     && sx + boxW > -10 && sx < view.width + 10
            x: sx + (boxW - artW) / 2
            y: sy - ink.inkTopPx(modelData.glyph, glyphPx)
            transform: Scale {
                origin.x: 0
                origin.y: 0
                xScale: view.stretchX
            }
            text: artRows.join("\n")
            color: view.platColor(modelData)
            font.family: "monospace"
            font.pixelSize: glyphPx
            font.bold: !!modelData.edge
            font.features: ink.artFontFeatures   // keep the art a plain grid
            lineHeight: 1.0   // keep multi-row art (finish band) tight
        }
    }

    // ---- hazards: the mode's falling rocks (Asterisk Attack) and collectible
    // glyphs (Glyph Hunt) ----
    // Constant model (the pool's slot count), so a spawn never recreates a
    // delegate; only bindings change. A size class is the glyph's ink *width*,
    // so the font size comes from the measured ratio of the character *this
    // slot* draws, and the ink box sits on the simulated centre. A collect mode
    // paints each drop in the player colour it was stamped with (p1Color or
    // p2Color, never a third ink); hazard modes paint platColors by size class.
    Repeater {
        model: view.engine.hazardMax
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property int sz: view.engine.hazardSizeAt(index)
            readonly property var hazard: view.engine.mode.hazard
            readonly property string glyph: view.engine.hazardGlyphAt(index)
            // which player's colour this drop belongs to (-1 = not a collect mode)
            readonly property int team: view.engine.hazardTeamAt(index)
            readonly property color paint: (hazard && hazard.teams)
                ? (team === 0 ? view.p1Color : view.p2Color)
                : (view.platColors[sz] || view.platColors[0])
            readonly property real boxW: (sz >= 0 && hazard) ? hazard.sizes[sz] : 0
            readonly property real fontPx: boxW
                / Math.max(0.05, ink.hazardInkWidthRatio[glyph] || 0.6)
            readonly property real sx: (view.engine.hazardXAt(index) - view.camX) * view.scaleX
            readonly property real sy: (view.engine.hazardYAt(index) - view.camY) * view.scaleY
            visible: sz >= 0 && sy > -40 && sy < view.height + 40
                     && sx > -40 && sx < view.width + 40
            width: ink.hazardInkWidthPx(glyph, fontPx)
            x: sx - boxW / 2 - ink.hazardInkLeftPx(glyph, fontPx)
            y: sy - ink.hazardInkCenterPx(glyph, fontPx)
            text: glyph
            color: paint
            font.family: "monospace"
            font.pixelSize: fontPx
            font.features: ink.artFontFeatures
            z: 3          // in front of the tower and the players it is falling on
            transform: Scale {
                origin.x: 0
                origin.y: 0
                xScale: view.stretchX
            }
        }
    }

    // ---- power-up: the bold "O" released at platform 50 (Asterisk Attack) ----
    // One slot per player. It is the player's own glyph in that player's glowing
    // colour, and only its owner can collect it.
    Repeater {
        model: 2
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property bool live: view.engine.powerupLive(index)
            readonly property color base: index === 0 ? view.p1Color : view.p2Color
            readonly property real sx: (view.engine.powerupXAt(index) - view.camX) * view.scaleX
            readonly property real sy: (view.engine.powerupYAt(index) - view.camY) * view.scaleY
            visible: live && index === view.selfIdx
                     && sy > -40 && sy < view.height + 40
                     && sx > -40 && sx < view.width + 40
            text: view.playerGlyph
            color: view.glowInk(base, powerPulse, view.hitGlowFill)
            // placed on the world point through the measured ink, so the box
            // and the glyph agree
            x: sx - width / 2
            y: sy - (ink.playerInkBottomPx(view.playerGlyph, view.playerFontPx)
                     - ink.playerInkHeightPx(view.playerGlyph, view.playerFontPx) / 2)
            font.family: "monospace"
            font.pixelSize: view.playerFontPx
            font.bold: true
            font.features: ink.artFontFeatures
            z: 3
            // fixed animation, never restarted per event
            property real powerPulse: 0.4
            SequentialAnimation on powerPulse {
                loops: Animation.Infinite
                NumberAnimation { to: 1.0; duration: 700; easing: Easing.InOutSine }
                NumberAnimation { to: 0.4; duration: 700; easing: Easing.InOutSine }
            }
            transform: Scale {
                origin.x: width / 2
                origin.y: 0
                xScale: view.stretchX
            }
        }
    }

    // ---- finish orb: the round ends when this is touched ----
    // Drawn in every pane, above the tower and behind the glyphs. Two circles, the
    // halo and the orb, both sized through the measured ink box so the paint lands
    // on engine orbX/orbY.
    Repeater {
        model: 2
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property bool halo: index === 0
            // halo: wider than the orb (glow, not hitbox)
            readonly property real px: view.orbFontPx * (halo ? 1.12 : 1.0)
                * view.orbScale
            readonly property real sx: (view.engine.orbX - view.camX) * view.scaleX
            readonly property real sy: (view.engine.orbY - view.camY) * view.scaleY
            visible: view.orbVisible && sx > -60 && sx < view.width + 60
                     && sy > -60 && sy < view.height + 60
            text: view.orbGlyph
            // the halo is the same circle, dimmer and wider; no blur here
            color: view.orbRamp(view.engine.orbBrightPulse)
            opacity: halo ? 0.30 : 1.0
            width: ink.orbInkWidthPx(view.orbGlyph, px)
            x: sx - ink.orbInkWidthPx(view.orbGlyph, px) / 2 - ink.orbInkLeftPx(view.orbGlyph, px)
            y: sy - ink.orbInkCenterPx(view.orbGlyph, px)
            font.family: "monospace"
            font.pixelSize: px
            font.features: ink.artFontFeatures
            z: halo ? 2.5 : 2.6     // over the platforms, under the players
            transform: Scale {
                origin.x: 0
                origin.y: 0
                xScale: view.stretchX
            }
        }
    }

    // ---- players: both drawn here, whichever pane this is ----
    Repeater {
        model: view.engine.p2Joined ? 2 : 1
        delegate: Item {
            id: playerItem
            required property int index

            readonly property bool isP1: index === 0
            readonly property real wx: isP1 ? view.engine.p1x : view.engine.p2x
            readonly property real wy: isP1 ? view.engine.p1y : view.engine.p2y
            readonly property real sx: (wx - view.camX) * view.scaleX
            readonly property real sy: (wy - view.camY) * view.scaleY
            // feet (collision bottom) in pane pixels; the glyph's painted bottom
            // lands exactly on that line, the platform's painted top
            readonly property real feetY: (wy + view.engine.playerH - view.camY) * view.scaleY
            readonly property real glyphW: 20 * view.scaleX
            readonly property real glyphH: 20 * view.scaleY
            readonly property bool gliding: isP1 ? view.engine.p1Gliding
                                                 : view.engine.p2Gliding
            readonly property real idleFor: isP1 ? view.engine.p1Idle : view.engine.p2Idle
            readonly property bool asleep: idleFor >= view.idleSeconds
                                           && !playerItem.shielded && !playerItem.orbHero
            readonly property string glyph: playerItem.impactTiny ? view.landingGlyph
                                             : (gliding ? view.glideGlyph
                                                : (playerItem.asleep
                                                   ? ((playerItem.blinking
                                                       || playerItem.blinks >= view.idleBlinks)
                                                      ? view.blinkGlyph : view.idleGlyph)
                                                   : view.playerGlyph))
            // riding the other glyph: drop by the carrier's painted-head offset so
            // the rider's feet touch the art, not its box top
            readonly property bool onHead: isP1 ? view.engine.p1OnHead
                                               : view.engine.p2OnHead
            readonly property string carrierGlyph: (isP1 ? view.engine.p2Gliding
                                                         : view.engine.p1Gliding)
                                                   ? view.glideGlyph : view.playerGlyph
            readonly property real headSink: onHead
                ? view.engine.playerH * view.scaleY
                  - ink.playerInkHeightPx(carrierGlyph, view.playerFontPx)
                : 0
            readonly property bool offAbove: sy < -12
            readonly property bool offBelow: sy > view.height + 12
            readonly property bool offLeft: sx + glyphW < 0
            readonly property bool offRight: sx > view.width
            readonly property bool off: offAbove || offBelow || offLeft || offRight
            // fell past the arena floor: show the death marker, not a pinned glyph
            readonly property bool inAbyss: wy > view.engine.baseH
            readonly property int ghostIdx: isP1 ? 0 : 1

            x: offLeft ? 4 : (offRight ? view.width - glyphW - 4 : sx)
            y: offAbove ? 6 : (offBelow ? view.height - glyphH - 6
                                        : feetY - ink.playerInkBottomPx(glyph, playerItem.fontPx)
                                          + headSink)   // drop onto the painted head
            width: glyphW
            height: glyphH
            z: 2

            // Ghost trail: a crossed O per fall, newest brightest. Constant model
            // (slot count), so a death only updates bindings.
            Repeater {
                model: view.engine.ghostMax
                delegate: Text {
                    textFormat: Text.PlainText
                    required property int index
                    readonly property int age: view.engine.ghostAge(playerItem.ghostIdx, index)
                    // world-anchored like platforms: feet sit on the marker's own
                    // world y (the arena floor line for a fall, the death spot for
                    // a rock kill), so the marks scroll with the camera
                    readonly property real ghostWy: view.engine.ghostYAt(playerItem.ghostIdx, index)
                    readonly property real ghostPaneY: (ghostWy - view.camY) * view.scaleY
                        - ink.playerInkBottomPx(view.deathGlyph, view.playerFontPx)
                    // world x of the fallen glyph's *centre*. The marker is laid
                    // out exactly like the player Text (glyph-wide box, advance
                    // centred) so its ink lands where the O was
                    readonly property real ghostX: view.engine.ghostXAt(playerItem.ghostIdx, index)
                    readonly property real gx: Math.max(4,
                        Math.min(view.width - playerItem.glyphW - 4,
                                 (ghostX - view.camX) * view.scaleX - playerItem.glyphW / 2))
                    visible: age >= 0 && ghostPaneY > -60 && ghostPaneY < view.height + 60
                    x: gx - playerItem.x
                    y: ghostPaneY - playerItem.y
                    width: playerItem.glyphW
                    horizontalAlignment: Text.AlignHCenter
                    text: view.deathGlyph
                    color: playerItem.baseColor
                    opacity: 0.45 * (1 - age / (2 * view.engine.ghostMax))
                    font.family: "monospace"
                    font.pixelSize: 20 * view.scaleY
                    font.bold: false     // matches the regular player glyph it marks
                    transform: Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: view.stretchX
                    }
                }
            }

            property bool impactTiny: false
            Timer {
                id: tinyTimer
                interval: 150
                onTriggered: playerItem.impactTiny = false
            }

            // Idle blink: the plain o for ~110 ms, with irregular gaps (2.2-5.4 s).
            // Both timers are fixed per player, never created per event.
            property bool blinking: false
            property int blinks: 0
            onAsleepChanged: if (!playerItem.asleep) playerItem.blinks = 0
            Timer {
                id: blinkTimer
                interval: 2600
                running: playerItem.asleep && playerItem.blinks < view.idleBlinks
                repeat: true
                onRunningChanged: if (!running) playerItem.blinking = false
                onTriggered: {
                    playerItem.blinks = playerItem.blinks + 1;
                    interval = 2200 + Math.random() * 3200;
                    playerItem.blinking = true;
                    blinkClose.restart();
                }
            }
            Timer {
                id: blinkClose
                interval: 110
                onTriggered: playerItem.blinking = false
            }
            Connections {
                target: view.engine
                function onLanded(playerIdx) {
                    if (playerIdx !== playerItem.index) return;
                    playerItem.impactTiny = true;
                    tinyTimer.restart();
                }
            }

            property real hitGlow: 0
            NumberAnimation {
                id: glowAnim
                target: playerItem
                property: "hitGlow"
                from: 1.0
                to: 0.0
                duration: view.hitGlowSeconds * 1000
            }
            Connections {
                target: view.engine
                function onBumped() { glowAnim.restart() }
            }
            // the Glyph Hunt catch: a quicker, brighter flash of this player's own
            // colour, the answer to the bing. Wrong colour never gets here, it
            // kills instead (and _crush moves the glyph to the start pad).
            property real collectGlow: 0
            NumberAnimation {
                id: collectAnim
                target: playerItem
                property: "collectGlow"
                from: 1.0
                to: 0.0
                duration: view.collectGlowSeconds * 1000
            }
            Connections {
                target: view.engine
                function onCollected(playerIdx, correct) {
                    if (playerIdx !== playerItem.index || !correct) return;
                    collectAnim.restart();
                }
            }
            // the glyph wears the colour of the platform it can stand on, so in
            // Match or Fall it follows the form and elsewhere it is the player's own
            readonly property color baseColor: view.formColor(
                view.engine.mode.matchFall === true
                    ? (playerItem.isP1 ? view.engine.p1Form : view.engine.p2Form)
                    : playerItem.index)
            readonly property bool shielded: isP1 ? view.engine.p1Bold : view.engine.p2Bold
            // the player who touched the orb draws at the orb's font size; this
            // delegate reads fontPx throughout, so the painted feet stay put
            readonly property bool orbHero: view.engine.orbWinner === index
            readonly property real fontPx: orbHero ? view.orbFontPx : view.playerFontPx
            // charged: hold the glyph at a full flash, so a bump is never dimmer
            // than the charge; the orb hero rides the engine's brightness pulse.
            // Each source carries its own fill, and the strongest active one wins.
            readonly property real glowMix: Math.max(
                view.hitGlowFill * playerItem.hitGlow,
                view.collectGlowFill * playerItem.collectGlow,
                playerItem.shielded ? view.hitGlowFill : 0.0,
                playerItem.orbHero ? view.hitGlowFill * view.engine.orbBrightPulse : 0.0)
            readonly property color glowFill: view.glowInk(playerItem.baseColor, 1.0,
                playerItem.glowMix)

            // walking wobble: every footstep dips the glyph and springs it back, on
            // the engine's 0.3 s cadence. The glyph is *scaled*, never re-laid out
            // (a font-size animation would re-shape the text every frame).
            property real stepWobble: 1.0
            SequentialAnimation {
                id: wobbleAnim
                NumberAnimation {
                    target: playerItem
                    property: "stepWobble"
                    to: view.stepSquash
                    duration: 80
                    easing: Easing.OutQuad
                }
                NumberAnimation {
                    target: playerItem
                    property: "stepWobble"
                    to: 1.0
                    duration: 120
                    easing: Easing.OutBack
                }
            }
            Connections {
                target: view.engine
                function onStepped(playerIdx) {
                    if (playerIdx !== playerItem.index) return;
                    wobbleAnim.restart();
                }
            }

            Text {
                textFormat: Text.PlainText
                id: playerText
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.glyph
                      + (parent.offAbove ? "▲" : parent.offBelow ? "▼"
                         : parent.offLeft ? "◀" : parent.offRight ? "▶" : "")
                color: playerItem.glowFill
                opacity: parent.off ? 0.5 : 1.0
                // hidden while dropping into the abyss (no ▼ pin mid-fall): this
                // Text only, the ghost row in the same delegate must stay up
                visible: !parent.inAbyss
                font.family: "monospace"
                font.pixelSize: playerItem.fontPx
                // weight carries the charge and the catch: bold while shielded,
                // and for the first half of a collect flash, so the weight comes
                // back as the colour fades instead of popping at the end
                font.bold: playerItem.shielded || playerItem.collectGlow > 0.5
                transform: [
                    // walk wobble: uniform shrink about the *painted feet* (the
                    // delegate's y already puts the ink bottom on the ground), not
                    // the box bottom
                    Scale {
                        origin.x: playerText.width / 2
                        origin.y: ink.playerInkBottomPx(playerItem.glyph, playerItem.fontPx)
                        xScale: playerItem.stepWobble
                        yScale: playerItem.stepWobble
                    },
                    // horizontal stretch applied outside the wobble, so a squashed
                    // glyph stretches like the rest of the art (see stretchX)
                    Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: view.stretchX
                    }
                ]
            }
        }
    }

    // ---- pane HUD: whose camera this is ----
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 4
        width: tag.implicitWidth + 10
        height: tag.implicitHeight + 2
        radius: 3
        color: Util.alpha(Color.background, 0.72)
        border.width: 1
        border.color: Util.alpha(view.selfColor, 0.45)
        Text {
            textFormat: Text.PlainText
            id: tag
            anchors.centerIn: parent
            // Pane owner, the mode's goal and progress: `P1: 3_100 | Ø 4`. The
            // middle segment is the mode's tag glyph (`~` in the racing modes,
            // `$` in Glyph Hunt) plus either the platform count or the points
            // (`P1 | $ 3_10`). The death segment appears only once that player
            // has fallen.
            readonly property string tagGoal: view.engine.mode.tagGlyph
                                               ? view.engine.mode.tagGlyph + " " : ""
            readonly property string tagProgress: view.engine.scoreTarget > 0
                ? ((view.selfIdx === 0 ? view.engine.p1Score : view.engine.p2Score)
                   + "_" + view.engine.scoreTarget)
                : (view.selfPlat + "_" + (view.engine.platCount - 1))
            text: (view.isSelf ? "P1" : "P2")
                  + ": " + tagGoal + tagProgress
                  + (view.selfFalls > 0
                     ? " | " + view.deathGlyph + " " + view.selfFalls : "")
            color: view.selfColor
            font.family: "monospace"
            font.pixelSize: 10 * view.uiScale
            font.bold: true
        }
    }
}
