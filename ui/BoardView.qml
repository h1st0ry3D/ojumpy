import QtQuick
import qs.Commons

// Ojumpy viewport — one pane, one camera.
//
// The engine simulates in base units (440x500); a BoardView renders that world
// through a single camera (camX/camY = world coords at the pane's top-left
// corner), so the pane shows exactly view.width/scaleX by view.height/scaleY
// world units. GameBoard uses one BoardView for solo play and two side-by-side
// once player 2 joins, which is what gives each player an independent camera.
//
// Both glyphs render in every pane (P2 only once joined), so each player sees
// the other. A player outside the pane is pinned to the pane edge, dimmed and
// marked with a ▲▼◀▶ caret. Read-only over the engine: no game logic here.

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

    readonly property color selfColor: view.selfIdx === 0 ? view.p1Color : view.p2Color
    // start pad and finish line share one colour; the rest is graded by size
    function platColor(plat) {
        if (plat.idx === 0 || plat.idx === view.engine.platCount - 1) return view.edgeColor;
        return view.platColors[plat.sizeClass] || view.platColors[0];
    }
    readonly property bool isSelf: view.selfIdx === 0
    readonly property int selfPlat: view.isSelf ? view.engine.p1Plat : view.engine.p2Plat
    readonly property int selfFalls: view.isSelf ? view.engine.falls1 : view.engine.falls2

    // ---- glyph ink metrics ----
    // GlyphMetrics.qml owns the TextMetrics probes, the ink ratios and the
    // lookup helpers (see that file for why the numbers are what they are).
    // What the view declares here is *which* glyphs to measure: every platform
    // pattern plus the finish band, and the four player glyphs.
    readonly property string playerGlyph: "Ö"
    readonly property string glideGlyph: "Ô"   // O with a circumflex: the glider
    readonly property string deathGlyph: "Ø"   // crossed O: a death marker
    // Landing impact: the glyph drops to the plain `o` for a moment — the eyes
    // shut on touchdown, so a landing reads as a blink rather than as a different
    // letter (the same `o` the idle blink closes into).
    readonly property string landingGlyph: "o"
    // Idle: after `idleSeconds` without moving, a player is drawn as a small ö
    // whose dots blink — `blinkGlyph` is the plain o the eyes vanish into.
    readonly property string idleGlyph: "ö"
    readonly property string blinkGlyph: "o"
    readonly property real idleSeconds: 3
    // A dozing player blinks this many times, then stops: the eyes stay shut
    // (a steady `o`), which reads as "asleep" instead of "malfunctioning".
    readonly property int idleBlinks: 10
    // the mode's hazard glyph (Asterisk Attack's rock) — measured like the rest
    // of the text art, so a rock's ink box is its collision box
    readonly property string hazardGlyph: view.engine.mode.hazard
                                          ? view.engine.mode.hazard.glyph : "*"
    // How far a footstep dips the player glyph: the walk wobble scales the
    // glyph down to this and springs it back (the terminal reading of a
    // body squash-and-stretch, same 80/120 ms timings). Uniform, not the game's
    // wider/shorter squash: a smaller glyph reads as a bob.
    readonly property real stepSquash: 0.78


    GlyphMetrics {
        id: ink
        platformGlyphs: view.engine.glyphs.concat([view.engine.finishGlyph])
        playerGlyphs: [view.playerGlyph, view.glideGlyph, view.deathGlyph, view.landingGlyph,
                       view.idleGlyph, view.blinkGlyph]
        hazardGlyphs: [view.hazardGlyph]
        orbGlyphs: [view.orbGlyph]
    }

    // Advance of one character of a platform art, in font-size units — the
    // ripple grid steps by this. 0.6 em is the monospace advance the engine
    // sizes every platform with (see GameEngine.platCharW).
    readonly property real charAdvanceRatio: 0.6

    // Fullscreen can stretch the arena horizontally (scaleX != scaleY): the
    // engine's collision boxes use scaleX while text glyphs are sized from
    // scaleY, so world-space art is stretched by this factor to keep the painted
    // platform exactly as wide as the box it collides with. In the normal view
    // it is 1.
    readonly property real stretchX: view.scaleX / Math.max(0.0001, view.scaleY)

    readonly property real playerFontPx: 20 * view.scaleY

    // ---- finish orb ----
    // A filled circle hovering over the summit's centre, breathing between two
    // fixed colours — dark orange and light yellow — that do not come from the
    // theme: the goal has to read as the goal whatever palette the bar wears.
    readonly property string orbGlyph: "●"
    readonly property color orbDark: "#FF8C00"    // dark orange, at the low pulse
    readonly property color orbLight: "#FFFFE0"   // light yellow, at the high one
    // The engine owns the pulse (so the paint is exactly the hitbox); here it
    // just becomes a colour. Not a mix towards white: a real two-colour ramp,
    // which is what makes the glow legible from far away.
    function orbRamp(t) {
        return Qt.rgba(view.orbDark.r + (view.orbLight.r - view.orbDark.r) * t,
                       view.orbDark.g + (view.orbLight.g - view.orbDark.g) * t,
                       view.orbDark.b + (view.orbLight.b - view.orbDark.b) * t, 1.0)
    }
    // the engine fixes the radius, so the font size follows from the measured
    // ink height: a circle drawn exactly orbRNow wide, pulse included
    readonly property real orbFontPx: 2 * view.engine.orbRNow
        / Math.max(0.3, ink.orbInkHeightRatio[view.orbGlyph] || 0.7) * view.scaleY
    // 1 -> 0 over the engine's 0.18 s shrink once the orb is taken
    property real orbScale: 1.0
    // true once the shrink has finished (the shrink animates through the take,
    // so the orb stays drawn for those 180 ms)
    property bool orbGone: false
    readonly property bool orbVisible: !view.orbGone && view.engine.orbActive
        && (view.engine.roundActive || view.engine.orbTaken)

    // the orb shrinks to nothing on pickup
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
    // A hit lights both glyphs in a brighter shade of their own colour for
    // hitGlowSeconds, fading linearly. A glyph is one colour here, so the light
    // is that colour mixed towards white — and only the colour changes: the
    // glyph keeps its weight.
    readonly property real hitGlowSeconds: 0.35
    readonly property real hitGlowFill: 0.55    // mix towards white at full pulse
    function glowInk(base, pulse, amount) {
        if (pulse <= 0) return base;
        var t = amount * pulse;
        return Qt.rgba(base.r + (1.0 - base.r) * t,
                       base.g + (1.0 - base.g) * t,
                       base.b + (1.0 - base.b) * t, 1.0);
    }

    clip: true

    // ---- landing ripple ----
    // Every landing starts a bright wave at the impact point that runs outwards
    // over the platform's own characters (LandRipple.qml). Nothing is added to
    // the platform: the wave is an aligned per-character overlay, so the art
    // itself never changes. Fixed pool, no per-landing item creation.
    LandRipple {
        id: ripples
        z: 1.5          // above the platform art it lights up, below the players
        stretchX: view.stretchX
        camX: view.camX
        camY: view.camY
        scaleX: view.scaleX
        scaleY: view.scaleY
    }

    // The engine's landed() carries the platform's left edge, not the platform,
    // so the art (and the ink colour picked from it) is looked up by that edge.
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
            // drawn exactly as authored — one pattern per size, no repetition or
            // truncation — so the engine sizes each platform to its pattern's
            // own width; the art is centred on the collision box to absorb any
            // scaleX/scaleY rounding. Art may be multi-row (finish band).
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

    // ---- hazards: the mode's falling rocks (Asterisk Attack) ----
    // Constant model (the pool's slot count), like the ghost row, so a spawn
    // never recreates a delegate — only bindings change. The mode's size class
    // is the rock's ink *width*, so the font size is derived from the measured
    // ink ratio and the ink box is placed exactly on the simulated centre; the
    // colours are the platform palette's, by size class, as asked.
    Repeater {
        model: view.engine.hazardMax
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property int sz: view.engine.hazardSizeAt(index)
            readonly property var hazard: view.engine.mode.hazard
            readonly property real boxW: (sz >= 0 && hazard) ? hazard.sizes[sz] : 0
            readonly property real fontPx: boxW
                / Math.max(0.05, ink.hazardInkWidthRatio[view.hazardGlyph] || 0.6)
            readonly property real sx: (view.engine.hazardXAt(index) - view.camX) * view.scaleX
            readonly property real sy: (view.engine.hazardYAt(index) - view.camY) * view.scaleY
            visible: sz >= 0 && sy > -40 && sy < view.height + 40
                     && sx > -40 && sx < view.width + 40
            width: ink.hazardInkWidthPx(view.hazardGlyph, fontPx)
            x: sx - boxW / 2 - ink.hazardInkLeftPx(view.hazardGlyph, fontPx)
            y: sy - ink.hazardInkCenterPx(view.hazardGlyph, fontPx)
            text: view.hazardGlyph
            color: view.platColors[sz] || view.platColors[0]
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
    // One slot per player, falling down the arena's middle. It is the player's
    // own glyph, so it reads as "a spare you", and it glows in that player's
    // colour (brighter, pulsing) — the drop and the charged glyph then share one
    // look. Only its owner can catch it.
    Repeater {
        model: 2
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property bool live: view.engine.powerupLive(index)
            readonly property color base: index === 0 ? view.p1Color : view.p2Color
            readonly property real sx: (view.engine.powerupXAt(index) - view.camX) * view.scaleX
            readonly property real sy: (view.engine.powerupYAt(index) - view.camY) * view.scaleY
            // each pane only shows its own player's power-up: the drop is a
            // private reward (the engine only lets its owner collect it anyway),
            // so showing it to the opponent would just be a tease
            visible: live && index === view.selfIdx
                     && sy > -40 && sy < view.height + 40
                     && sx > -40 && sx < view.width + 40
            text: view.playerGlyph
            color: view.glowInk(base, powerPulse, view.hitGlowFill)
            // centred on the world point through the measured ink, like every
            // other bit of art here, so the collision box and the glyph agree
            x: sx - width / 2
            y: sy - (ink.playerInkBottomPx(view.playerGlyph, view.playerFontPx)
                     - ink.playerInkHeightPx(view.playerGlyph, view.playerFontPx) / 2)
            font.family: "monospace"
            font.pixelSize: view.playerFontPx
            font.bold: true
            font.features: ink.artFontFeatures
            z: 3
            // gentle glow: fixed animation, never restarted per event
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
    // Drawn in every pane (both players have to see the goal), above the tower
    // and behind the glyphs. Two circles: a soft halo and the orb itself, both
    // sized through the measured ink box so the paint lands on engine orbX/orbY.
    Repeater {
        model: 2
        delegate: Text {
            textFormat: Text.PlainText
            required property int index
            readonly property bool halo: index === 0
            // halo: a touch wider than the orb it belongs to (glow, not hitbox)
            readonly property real px: view.orbFontPx * (halo ? 1.12 : 1.0)
                * view.orbScale
            readonly property real sx: (view.engine.orbX - view.camX) * view.scaleX
            readonly property real sy: (view.engine.orbY - view.camY) * view.scaleY
            visible: view.orbVisible && sx > -60 && sx < view.width + 60
                     && sy > -60 && sy < view.height + 60
            text: view.orbGlyph
            // the halo is the same circle, dimmer and wider: the terminal
            // reading of an additive glow, which has no blur here
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
            // feet (collision bottom) in pane pixels; the glyph is drawn so
            // its painted bottom lands exactly on that line, i.e. on the
            // platform's painted top
            readonly property real feetY: (wy + view.engine.playerH - view.camY) * view.scaleY
            readonly property real glyphW: 20 * view.scaleX
            readonly property real glyphH: 20 * view.scaleY
            readonly property bool gliding: isP1 ? view.engine.p1Gliding
                                                 : view.engine.p2Gliding
            // An idle player sleeps: the Ö becomes a small ö whose dots blink
            // (see blinkTimer). A charge or the orb trophy outranks the nap — both
            // are states the player is meant to see.
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
            // standing on the other glyph: drop by the carrier's painted-head
            // offset so the rider's feet touch the art instead of its box top
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
            // fell past the arena floor: the view shows the death marker at the
            // bottom edge instead of pinning the falling glyph
            readonly property bool inAbyss: wy > view.engine.baseH
            readonly property int ghostIdx: isP1 ? 0 : 1

            x: offLeft ? 4 : (offRight ? view.width - glyphW - 4 : sx)
            y: offAbove ? 6 : (offBelow ? view.height - glyphH - 6
                                        : feetY - ink.playerInkBottomPx(glyph, playerItem.fontPx)
                                          + headSink)   // drop onto the painted head
            width: glyphW
            height: glyphH
            z: 2

            // Ghost trail: a crossed O per fall, newest brightest, on the pane's
            // bottom edge. Constant model (slot count), so a death only updates
            // bindings and never rebuilds delegates.
            Repeater {
                model: view.engine.ghostMax
                delegate: Text {
                    textFormat: Text.PlainText
                    required property int index
                    readonly property int age: view.engine.ghostAge(playerItem.ghostIdx, index)
                    // world-anchored like platforms: each marker's feet sit on
                    // its own world y (the arena floor line for a fall, the
                    // death spot when a rock got the player), so they scroll
                    // with the camera instead of riding the pane edge
                    readonly property real ghostWy: view.engine.ghostYAt(playerItem.ghostIdx, index)
                    readonly property real ghostPaneY: (ghostWy - view.camY) * view.scaleY
                        - ink.playerInkBottomPx(view.deathGlyph, view.playerFontPx)
                    // world x of the fallen glyph's *centre* — the marker is laid
                    // out exactly like the player Text (a glyph-wide box with the
                    // advance centred), so the ghost's ink lands on the spot the
                    // O had; drawing it as a left edge, as this row used to, put
                    // it one half-glyph off the fall
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
                    color: playerItem.isP1 ? view.p1Color : view.p2Color
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

            // landing impact: the big O drops to a small o for a moment, then
            // pops back — the player is drawn at the full glyph size otherwise
            property bool impactTiny: false
            Timer {
                id: tinyTimer
                interval: 150
                onTriggered: playerItem.impactTiny = false
            }

            // Idle blink: the ö's dots are the eyes, so a blink is the plain o for
            // ~110 ms. Blink gaps are irregular (2.2-5.4 s) — a fixed metronome
            // reads as a machine, not as a face. Both timers are fixed per player,
            // never created per event.
            property bool blinking: false
            // blinks spent in *this* nap: after view.idleBlinks the timer stops
            // running and the glyph stays on the closed-eye `o` (see the glyph
            // rule above), so a long idle ends up fast asleep rather than
            // twitching forever. Waking resets the count.
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

            // bump glow: hit pulse 1 -> 0 over hitGlowSeconds (see hitGlowFill),
            // restarted by every hit, so both players flash their own colour
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
            readonly property color baseColor: playerItem.isP1 ? view.p1Color : view.p2Color
            readonly property bool shielded: isP1 ? view.engine.p1Bold : view.engine.p2Bold
            // the player who touched the orb keeps the orb's size and a steady
            // glow for the rest of the round (the touching body fills up
            // and stays lit). Everything this delegate draws the glyph with reads
            // fontPx, so growing it keeps the painted feet on the same line.
            readonly property bool orbHero: view.engine.orbWinner === index
            readonly property real fontPx: orbHero ? view.orbFontPx : view.playerFontPx
            // charged: hold the glyph at a full flash (the normal state is bold
            // already, so the brighter ink is what reads as "shielded"), and a
            // bump can never be dimmer than the charge. The orb hero is lit on
            // the orb's own (engine-driven) brightness pulse, so the two read as
            // one thing.
            readonly property color glowFill: view.glowInk(playerItem.baseColor,
                Math.max(playerItem.hitGlow, playerItem.shielded ? 1.0 : 0.0,
                         playerItem.orbHero ? view.engine.orbBrightPulse : 0.0), view.hitGlowFill)

            // walking wobble: every footstep dips the glyph and springs it back.
            // Panel plays the matching step blip, so sound and motion share the
            // engine's 0.3 s cadence. The glyph is *scaled*, never re-laid out
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
                // hidden while dropping into the abyss (no ▼ pin mid-fall) — the
                // glyph only: the delegate also carries the ghost row, which must
                // stay on screen through a death
                visible: !parent.inAbyss
                font.family: "monospace"
                font.pixelSize: playerItem.fontPx
                // weight carries the charge: a regular glyph normally, bold
                // while shielded (the power-up drop is drawn bold as well, so
                // the pick-up and the charged state read as one thing)
                font.bold: playerItem.shielded
                transform: [
                    // walk wobble: uniform shrink about the *painted feet* (the
                    // delegate's y already puts that ink bottom on the ground),
                    // so a step squashes the glyph down onto the platform
                    // instead of lifting it off
                    Scale {
                        origin.x: playerText.width / 2
                        origin.y: ink.playerInkBottomPx(playerItem.glyph, playerItem.fontPx)
                        xScale: playerItem.stepWobble
                        yScale: playerItem.stepWobble
                    },
                    // fullscreen horizontal stretch, applied outside the wobble
                    // so the squashed glyph is stretched like the rest of the
                    // art (see stretchX)
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
            // Who this pane belongs to, what the mode's goal looks like, and how
            // far along that player is: `P1 | ~ 3_100 | Ø 4`. The middle segment
            // is the mode's own tag glyph (`~`, the start pad's character, in the
            // racing modes; the biggest collectible in Glyph Hunt) followed by either the
            // platform count in the bar label's `N_target` form or, in the collect
            // modes, the points — `P1 | $ 3_10`. Deaths are counted with the ghost
            // glyph, so the marker and the counter read as one thing; the segment
            // is dropped entirely while that player has not fallen.
            readonly property string tagGoal: view.engine.mode.tagGlyph
                                               ? view.engine.mode.tagGlyph + " " : ""
            readonly property string tagProgress: view.engine.scoreTarget > 0
                ? ((view.selfIdx === 0 ? view.engine.p1Score : view.engine.p2Score)
                   + "_" + view.engine.scoreTarget)
                : (view.selfPlat + "_" + (view.engine.platCount - 1))
            text: (view.isSelf ? "P1" : "P2")
                  + " | " + tagGoal + tagProgress
                  + (view.selfFalls > 0
                     ? " | " + view.deathGlyph + " " + view.selfFalls : "")
            color: view.selfColor
            font.family: "monospace"
            font.pixelSize: 10 * view.uiScale
            font.bold: true
        }
    }
}
