import QtQuick
import "GameModes.js" as Modes
import "Course.js" as Course

// Ojumpy game engine — non-visual simulation.
//
// All simulation happens in BASE units (440x500 arena, fixed physics
// constants). Views scale positions/sizes for rendering only, so toggling
// fullscreen or resizing never touches game state: positions, platform
// placement (roundSeed) and the round timer are naturally preserved.
//
// The engine owns the rules dispatch: mode hooks (GameModes.js) decide
// wins/ends. Views must only read state, never mutate it — go through the
// API functions (startRound, stopGame, tick).

Item {
    id: engine

    // ---- base-unit arena + physics (never scaled, never mutated) ----
    readonly property int baseW: 440
    readonly property int baseH: 500
    readonly property int platBaseY: 458
    readonly property int playerH: 22
    readonly property real gravity: 1800
    readonly property real moveSpeed: 250
    readonly property real jumpVel: -440
    readonly property real maxFall: 950

    // ---- glide (hold jump while falling) ----
    // After at least one jump, holding jump while descending scales gravity down
    // and clamps the fall, so a held press floats the player across a gap. The
    // view draws the glider glyph (Ô) while active.
    readonly property real glideGravityMult: 0.35
    readonly property real glideFall: 110
    // vertical overlap (base units) above which a player pair counts as a side
    // hit rather than a rider standing on a head
    readonly property real sideTouch: 3
    // Side-by-side bodies separate only until their painted glyphs touch: the
    // monospace "O" ink is 0.44 em, i.e. 8.8 of the 20-unit player font, so
    // pushing to the full collision box (playerW) would leave a visible gap.
    readonly property real sideBodyW: 8.8

    // ---- footsteps (walk cadence) ----
    // One step every stepInterval while a player moves along a floor; the timer
    // resets when the walk stops, so the first step of a walk is immediate. The
    // view wobbles the glyph and Panel plays the cue off stepped(), so both share
    // this one cadence.
    readonly property real stepInterval: 0.3

    // ---- player-vs-player hits ----
    // A hit fires on the rising edge of contact and is then ignored for
    // hitCooldown, so leaning on the other player keeps shoving without
    // retriggering the bump every frame.
    readonly property real hitCooldown: 0.3

    // Platform spacing comes from the jump arc (max height = v^2 / 2g, taken as
    // a fixed fraction of the apex), so every hop is one committed,
    // always-reachable jump — reachability by construction, not by scattering
    // random heights.
    readonly property real jumpHeight: (jumpVel * jumpVel) / (2 * gravity)
    readonly property real climbRatio: 0.75
    readonly property real climbUnit: Math.round(jumpHeight * climbRatio)   // one climb unit

    // ---- course generation ----
    // Heights sit on a discrete grid of climb units (single +1, double +2,
    // bridge ±0), so every hop is exactly one committed jump; the walk itself,
    // its validation and the three-size pool live in Course.js.
    //
    // Art is one pattern per size, drawn exactly as authored, so a platform's
    // collision width is the pattern's own width: the renderer draws a 15-unit
    // monospace font at a 0.6 em advance, i.e. 9 base units per character
    // (>>><<< 63, ========= 81, <<<<<<>>>>>> 108, start pad 117, band 126).
    readonly property real platCharW: 9
    readonly property var platSizes: [7 * platCharW, 9 * platCharW, 12 * platCharW]
    readonly property int platCount: 101          // platforms 0..100
    readonly property real basePlatW: 13 * platCharW   // start island (`~` pattern)
    readonly property real goalPlatW: 14 * platCharW   // finish band (▀▄ pattern)
    readonly property int basePlatX: 40
    readonly property int genMinGap: 26           // smallest edge-to-edge gap
    readonly property int genClimbGapMax: 64      // longest single/double hop
    readonly property int genBridgeGapMin: 66     // flat crossing == long jump
    readonly property int genBridgeGapMax: 104
    readonly property int genEdge: 8              // arena margin

    // ---- mode ----
    property string modeId: "race"
    readonly property var mode: Modes.get(modeId)
    onModeIdChanged: if (!Modes.isReady(modeId)) modeId = "race"

    // best clear time per mode (ms). Storage/persistence lives in the panel
    // (bestFile); the engine only keeps the current values.
    property var bestByMode: ({})
    function bestFor(id) {
        var v = bestByMode[id];
        return isFinite(v) ? v : -1;
    }

    // ---- round state ----
    // platform.sizeClass: 0 = smallest, 1 = middle, 2 = longest, -1 = start
    // island / finish line — the view picks the paint colour from it
    property int roundSeed: 0
    property var platforms: []
    property bool roundActive: false
    property real elapsed: 0
    property double startStamp: 0
    // Pause: the sim clock stops. `paused` freezes tick() outright — players,
    // rocks, ghosts and the timer all hold still — and resumeGame() shifts
    // startStamp, so the frozen stretch is never charged to the run. The panel
    // pauses automatically when it leaves the screen (see Panel.onOpenedChanged)
    // and P toggles it either way; a new round always starts unpaused.
    property bool paused: false
    property double pauseStamp: 0
    property string winner: ""
    property string winnerGlyph: ""
    property real winTime: 0
    property int falls1: 0
    property int falls2: 0
    property bool p1done: false
    property bool p2done: false
    property bool p2Joined: false     // solo start; J joins player 2 (split screen)
    property bool sideTouching: false // side contact held (edge detection)
    property real hitCd: 0            // seconds left of the post-hit cooldown

    // ---- player state (base units) ----
    property real p1x: 60
    property real p1y: 400
    property real p1vy: 0
    property bool p1ground: true
    property int p1Plat: 0
    // seconds until this player's next footstep (see stepInterval)
    property real p1StepT: 0
    property real p2x: 120
    property real p2y: 400
    property real p2vy: 0
    property bool p2ground: true
    property int p2Plat: 0
    property real p2StepT: 0

    // ---- cameras (tower-climb style, view only) ----
    // One camera per player. Solo the board is a single 440x500 viewport
    // driven by camY1/camX1; once player 2 joins the board splits into two
    // side-by-side viewports (vertical divider, 220x500 each) so both panes
    // keep the full climb height, and each pane follows its own player in
    // both axes (smoothed), clamped to the arena. Base units, never scaled;
    // lives in the engine so all views share state.
    property real camY1: 0
    property real camY2: 0
    property real camX1: 0
    property real camX2: 0
    readonly property real camLead: 0.4   // player sits 40% down its viewport
    readonly property real splitViewW: baseW / 2   // split pane width (windowed)
    // Fullscreen panes are not half-width: the layout has the room, so each
    // player gets a whole arena-width view (the board grows to 2 x baseW
    // instead of splitting baseW in two). Set by the view.
    property bool wideView: false
    readonly property real viewportW: (p2Joined && !wideView) ? splitViewW : baseW
    readonly property real playerW: 20    // glyph hit box width, base units

    // ---- input (base velocity in {-1,0,1} + jump), pushed by the view ----
    property int p1Vx: 0
    property bool p1JumpHeld: false
    property int p2Vx: 0
    property bool p2JumpHeld: false

    // Double jump: the 2nd jump adds double_jump_height_mult times the 1st
    // jump's apex height again (velocity scales by sqrt(mult)). mult=1.0 →
    // the 2nd jump equals one more full single-jump unit. Pressed early it
    // replaces weaker upward velocity (never cancels it).
    readonly property real doubleJumpHeightMult: 1.0
    property int p1Jumps: 0   // jumps used since last grounded (0..2)
    property int p2Jumps: 0
    property bool p1JumpWas: false
    property bool p2JumpWas: false
    property bool p1Gliding: false   // jump held while falling (view shows Ô)
    property bool p2Gliding: false
    property bool p1OnHead: false    // resting on P2's head (view drops the rider
    property bool p2OnHead: false    // so its feet touch the painted head)
    // Ghost trail: where a player dropped off the tower, kept for the rest of
    // the round so the view can mark that spot instead of pinning the falling
    // glyph. A ring buffer with stable slots, not a growing list: the view then
    // has a constant model, so a death never recreates delegates.
    readonly property int ghostMax: 99
    // Ghosts are world-anchored like platforms: their feet sit on their own
    // world y, so they scroll with the camera instead of riding the bottom edge
    // of the pane. A fall leaves its marker on this arena y (the floor line);
    // a hazard death leaves it where the player was standing.
    readonly property real ghostY: baseH
    // slot -> where the dead glyph's *centre* was (float, world units — the view
    // lays the marker out like the player glyph, so an unrounded centre is what
    // keeps the ghost on the exact spot)
    property var p1GhostX: []
    property var p1GhostY: []      // slot -> world y of the marker's feet
    property var p1GhostSeq: []    // slot -> death index that filled it
    property int p1GhostDeaths: 0
    property var p2GhostX: []
    property var p2GhostY: []
    property var p2GhostSeq: []
    property int p2GhostDeaths: 0

    function ghostAge(idx, slot) {
        var seqs = idx === 0 ? p1GhostSeq : p2GhostSeq;
        if (seqs[slot] === undefined) return -1;
        return (idx === 0 ? p1GhostDeaths : p2GhostDeaths) - 1 - seqs[slot];
    }
    function ghostXAt(idx, slot) {
        var slots = idx === 0 ? p1GhostX : p2GhostX;
        return slots[slot] === undefined ? 0 : slots[slot];
    }

    // World y of a marker's feet: the floor line for a fall, the death spot for
    // a hazard hit (see _crush).
    function ghostYAt(idx, slot) {
        var slots = idx === 0 ? p1GhostY : p2GhostY;
        return slots[slot] === undefined ? ghostY : slots[slot];
    }

    // ---- hazards: the mode's falling glyphs (Asterisk Attack) ----
    // Fixed pool of stable slots, like the ghost ring: the view renders every
    // slot and hides the dead ones, so a spawn never rebuilds delegates. The
    // mode owns the tuning (`mode.hazard`); a mode without that block spawns
    // nothing and drops whatever is still falling.
    readonly property int hazardMax: 40    // headroom for the tripled rate
    property var hazX: []          // slot -> centre x (world units, float)
    property var hazY: []          // slot -> centre y
    property var hazSize: []       // slot -> size class 0..2, -1 = empty slot
    property var hazAng: []        // slot -> signed angle off vertical (radians)
    property int hazNext: 0        // round-robin slot for the next rock
    property real hazTimer: 0      // seconds since the last spawn
    property real hazGap: 1.0      // seconds until the next spawn (re-rolled)
    // LCG state, seeded from the round seed. MUST be real, not int: the state is
    // an unsigned 32-bit value, and a QML `int` is signed — storing it there
    // wrapped negative and every draw came out negative (rocks biased to the
    // left, size classes below 0, angles under the minimum).
    property real hazSeed: 1

    function hazardSizeAt(slot) {
        var v = hazSize[slot];
        return v === undefined ? -1 : v;
    }

    function hazardXAt(slot) { return hazX[slot] === undefined ? 0 : hazX[slot]; }
    function hazardYAt(slot) { return hazY[slot] === undefined ? 0 : hazY[slot]; }

    // the character this slot draws: collect modes use one per size class
    function hazardGlyphAt(slot) {
        var cfg = mode.hazard;
        if (!cfg) return "*";
        var sz = hazardSizeAt(slot);
        if (sz < 0) return cfg.glyph;
        return (cfg.glyphs && cfg.glyphs[sz] !== undefined) ? cfg.glyphs[sz] : cfg.glyph;
    }

    function hazardTeamAt(slot) {
        var t = hazTeam[slot];
        return (t === 0 || t === 1) ? t : -1;
    }

    function hazardCount() {
        var n = 0;
        for (var s = 0; s < hazardMax; s++)
            if (hazSize[s] !== undefined && hazSize[s] >= 0) n++;
        return n;
    }

    function clearHazards() {
        hazX = []; hazY = []; hazSize = []; hazAng = []; hazTeam = [];
        hazNext = 0; hazTimer = 0; hazGap = 0;
    }

    // ---- power-up: the bold "O" a hazard mode releases at platform 50 -------
    // One per player, down the middle of the arena. Catching it charges them
    // (they survive one rock hit, glyph glowing in their own colour); the hit
    // spends the charge and the glyph goes back to normal.
    property var pow50: [false, false]     // slot = owner: the platform-50 one is out?
    property var powLive: [false, false]   // slot = owner: still falling?
    property var powY: [0, 0]              // slot -> centre y (world)
    property var powX: [baseW / 2, baseW / 2]   // slot -> centre x (world)
    readonly property real powFall: 120    // slower than the rocks: catchable
    property bool p1Bold: false
    property bool p2Bold: false

    function boldFor(idx) { return idx === 0 ? p1Bold : p2Bold; }
    function powerupLive(idx) { return powLive[idx] === true; }
    function powerupYAt(idx) { return powY[idx] === undefined ? 0 : powY[idx]; }
    function powerupXAt(idx) { return powX[idx] === undefined ? baseW / 2 : powX[idx]; }

    function clearPowerups() {
        pow50 = [false, false];
        powLive = [false, false];
        powY = [0, 0];
        powX = [baseW / 2, baseW / 2];
        p1Bold = false; p2Bold = false;
    }

    function _resetPowerupSlot(idx) {
        var t = pow50.slice(); t[idx] = false; pow50 = t;
        var l = powLive.slice(); l[idx] = false; powLive = l;
        var y = powY.slice(); y[idx] = 0; powY = y;
        var x = powX.slice(); x[idx] = baseW / 2; powX = x;
        if (idx === 0) p1Bold = false; else p2Bold = false;
    }

    // Release a drop above a given world x / y (the arena middle for the
    // platform-50 one, the respawn spot for a death reward).
    function _dropPowerup(idx, x, y) {
        var l = powLive.slice(); l[idx] = true; powLive = l;
        var ys = powY.slice(); ys[idx] = y; powY = ys;
        var xs = powX.slice(); xs[idx] = x; powX = xs;
    }

    // Every `powerupDeaths` deaths hands one back: it falls onto the player as
    // they respawn at the start, so a bad round has a way out. Skipped while
    // they are already charged — a charge does not stack.
    function _rewardDeath(idx) {
        var cfg = Modes.get(modeId).hazard;
        if (!cfg || !cfg.powerupDeaths || cfg.powerupDeaths <= 0) return;
        var deaths = idx === 0 ? falls1 : falls2;
        if (deaths <= 0 || deaths % cfg.powerupDeaths !== 0) return;
        if (boldFor(idx)) return;
        // Dropped from the top, like the platform-50 one enters its pane: world
        // 0 is the top edge of the *start* view (camTargetYFor clamps a
        // bottom-of-tower camera to 0), so this falls the whole way down the
        // pane onto the pad the player just respawned on — a visible approach
        // rather than something handed over on the spot.
        var spot = _startSpot(idx);
        _dropPowerup(idx, spot.x + playerW / 2, -24 - playerH / 2);
    }
    function ghostCount(idx) {
        var seqs = idx === 0 ? p1GhostSeq : p2GhostSeq;
        var n = 0;
        for (var i = 0; i < seqs.length; i++) if (seqs[i] !== undefined) n++;
        return n;
    }

    // Platform art: smallest >>><<<, middle =========, longest <<<<<<>>>>>>,
    // plus the start pad at index 0. The generator maps sizes to 1..3.
    readonly property var glyphs: [
        "~~~~~~~~~~~~~",      // start pad (platform 0)
        ">>><<<",             // smallest size
        "=========",          // middle size
        "<<<<<<>>>>>>"        // longest size
    ]
    // Finish line: one checkered band of half blocks (upper/lower alternating).
    // The final platform is drawn with it and its painted top is where the players
    // land, so the band reads as the line they finish on. One row, not two: a
    // single row of mixed ▀/▄ is one continuous band with a single ink box, which
    // is also what the landing ripple needs to place its wave (two rows made the
    // ripple measure half-block rows and draw its cells against the wrong band).
    readonly property string finishGlyph: "▀▄▀▄▀▄▀▄▀▄▀▄▀▄"

    // ---- the finish orb ----
    //
    // The summit carries a glowing orb instead of a finish *line*: the round ends
    // when someone touches it, never by merely standing on the last platform. It
    // hovers a little above that platform's centre — high enough that standing on
    // it does not count (see orbHover), so you jump into it, and low enough that a
    // jump from the platform below can catch it on the way up.
    //
    // Colour and behaviour are fixed: C_YELLOW #E7E8A8 (not themed —
    // the goal has to read the same in every palette), a slow size pulse and a
    // faster brightness pulse (the view draws both), a 0.18 s shrink when taken,
    // and the touching player's glyph growing to the orb's size and lighting up
    // for the rest of the round.
    // Modes can opt out of the orb: Glyph Hunt's goal is the score, and the orb
    // would be an easier second win condition (race up instead of hunting).
    readonly property bool orbActive: mode.orb !== false
    readonly property real orbHover: 40   // orb centre above the summit surface
    readonly property real orbR: 9.5      // painted radius at the pulse's smallest
    // The orb breathes: its radius grows by this much at the pulse peak and its
    // colour rides the same clock (the view ramps dark orange -> light yellow).
    // 0.18 is deliberately visible from the far end of the arena — the earlier
    // 5 % never read as movement.
    readonly property real orbGrow: 0.18
    // The pulse lives *here*, derived from the run clock, not as a view
    // animation: the orb is a target, so whatever is painted has to be what is
    // collided with. Two rates — the size breathes at 2 rad/s, the
    // colour at 4 rad/s. Both are 0..1.
    property real orbSizePulse: 0
    property real orbBrightPulse: 0
    readonly property real orbRNow: orbR * (1 + orbGrow * orbSizePulse)
    // The orb is touched by the *painted* body, ink height included: standing on
    // the summit leaves a gap (the painted top of an Ö is 17.4 above the feet
    // line, the orb's bottom 49.5), while any jump puts the ink straight through
    // it even though the orb's bottom rises with the taller ink: the widest
    // contact window is orbRNow + paintedH/2 = 20.3 at the pulse peak against a
    // standing gap of 31.3, so a merely standing player never collects it. Rocks
    // still use the taller collision box — that rule is tuned and separate.
    readonly property real paintedH: 17.4
    property real orbX: 0
    property real orbY: 0
    property bool orbTaken: false
    property int orbWinner: -1

    // Idle seconds per player: counts while a glyph stands still and nothing is
    // asked of it, resets the moment it moves, jumps or glides. The view uses it
    // to put the player to sleep (a small ö that blinks); a paused round does not
    // step at all, so the count freezes with the rest of the sim.
    property real p1Idle: 0
    property real p2Idle: 0

    // Glyph Hunt (hazard.teams): every falling glyph is stamped with one
    // player's colour at spawn, and touching it scores for that player (+1) or
    // costs the other one (-1, floored at zero). Nothing here kills.
    property int p1Score: 0
    property int p2Score: 0
    property var hazTeam: []
    readonly property int scoreTarget: (mode.hazard && mode.hazard.teams
                                        && mode.hazard.target) ? mode.hazard.target : 0
    signal orbCollected(int playerIdx)
    // a Glyph Hunt pickup: `correct` says whether it was the player's colour
    signal collected(int playerIdx, bool correct)
    // a jump left the ground (the ground jump and the air jump alike, as in
    // one cue per jump)
    signal jumped(int playerIdx)

    signal roundStarted()
    signal roundEnded(int playerIdx, real timeSec)
    // Emitted on every platform landing: the view answers with a landing ripple
    // on that platform (LandRipple.qml) and squashes the player glyph.
    signal landed(int playerIdx, real x, real platX, real platW, real platTop, string glyph)
    // One footstep: the cadence loop in _stepPlayer fired while this player was
    // walking on the floor. The view wobbles the glyph, Panel plays the blip.
    signal stepped(int playerIdx)
    // A real side hit between the two players (a rider on a head is not a hit):
    // Panel answers with the bump thud.
    signal bumped()
    // A hazard (Asterisk Attack's "*" rocks) killed a player: the panel plays
    // the hit cue, the view has already got the death marker through the ghost
    // ring.
    signal crushed(int playerIdx)
    // Picked up the platform-50 power-up / spent it absorbing a rock
    signal powered(int playerIdx)
    signal shielded(int playerIdx)

    function fmtTime(t) {
        if (!isFinite(t)) return "--";
        return t.toFixed(2) + "s";
    }

    // The walk itself is in Course.js (config + seed in, course out). The tuning
    // stays here because it is part of the simulation's contract: the view
    // measures art against platCharW, the jump budget against gravity/jumpVel.
    readonly property var courseConfig: ({
        baseW: baseW, platBaseY: platBaseY, climbUnit: climbUnit,
        platSizes: platSizes, platCount: platCount,
        basePlatW: basePlatW, goalPlatW: goalPlatW, basePlatX: basePlatX,
        genMinGap: genMinGap, genClimbGapMax: genClimbGapMax,
        genBridgeGapMin: genBridgeGapMin, genBridgeGapMax: genBridgeGapMax,
        genEdge: genEdge, glyphs: glyphs, finishGlyph: finishGlyph
    })

    // Deterministic level: same seed => same course (base units).
    function buildPlatforms() {
        return Course.build(courseConfig, roundSeed);
    }

    function startRound(seed) {
        roundSeed = (seed !== undefined && seed) ? seed : ((Date.now() % 2147483647) || 12345);
        platforms = buildPlatforms();
        // hazard pool + its generator, so the rocks follow the round's seed
        clearHazards();
        clearPowerups();
        hazSeed = ((roundSeed ^ 0x9e3779b9) >>> 0) || 1;
        var s = platforms[0];
        p1x = s.x + 18; p1y = s.y - playerH; p1vy = 0; p1ground = true; p1done = false; p1Jumps = 0; p1JumpWas = false;
        p1Plat = 0;
        p1StepT = 0;
        falls1 = 0;
        p1Gliding = false;
        p1GhostX = []; p1GhostY = []; p1GhostSeq = []; p1GhostDeaths = 0;
        resetP2();
        camX1 = camTargetXFor(0); camY1 = camTargetYFor(0);
        camX2 = p2Joined ? camTargetXFor(1) : camX1;
        camY2 = p2Joined ? camTargetYFor(1) : camY1;
        winner = ""; winnerGlyph = ""; winTime = 0;
        elapsed = 0; startStamp = Date.now();
        paused = false;
        p1Idle = 0; p2Idle = 0;
        p1Score = 0; p2Score = 0;
        _placeOrb();
        roundActive = true;
        roundStarted();
    }

    // ---- pause / resume ----
    function pauseGame() {
        if (!roundActive || paused) return;
        paused = true;
        pauseStamp = Date.now();
    }

    function resumeGame() {
        if (!paused) return;
        paused = false;
        startStamp += Date.now() - pauseStamp;
    }

    function togglePause() {
        if (paused) resumeGame(); else pauseGame();
    }

    function stopGame() {
        roundActive = false;
        paused = false;
        clearHazards();
        clearPowerups();
        winner = ""; winnerGlyph = ""; winTime = 0; elapsed = 0;
        p1Idle = 0; p2Idle = 0;
        p1Score = 0; p2Score = 0;
        _placeOrb();
        var s = platforms.length > 0 ? platforms[0] : { x: 60, y: platBaseY, w: 120 };
        p1x = s.x + 18; p1y = s.y - playerH; p1vy = 0; p1ground = true; p1done = false; p1Jumps = 0; p1JumpWas = false;
        p1Plat = 0;
        p1StepT = 0;
        falls1 = 0;
        p1Gliding = false;
        p1GhostX = []; p1GhostY = []; p1GhostSeq = []; p1GhostDeaths = 0;
        resetP2();
        camX1 = camTargetXFor(0); camY1 = camTargetYFor(0);
        camX2 = p2Joined ? camTargetXFor(1) : camX1;
        camY2 = p2Joined ? camTargetYFor(1) : camY1;
    }

    // ---- player 2: join / leave (round always starts solo) ----
    // Joining spawns P2 on platform 0 and splits the board into two viewports
    // with one camera each; both glyphs render in both viewports. Position and
    // fall counters reset so a joiner starts clean (mid-round joins included).
    function resetP2() {
        var s = platforms.length > 0 ? platforms[0] : { x: 60, y: platBaseY, w: 120 };
        p2x = s.x + s.w - 32; p2y = s.y - playerH; p2vy = 0; p2ground = true;
        p2done = false; p2Jumps = 0; p2JumpWas = p2JumpHeld; p2Plat = 0;
        p2StepT = 0;
        sideTouching = false; hitCd = 0;
        p2Gliding = false;
        _resetPowerupSlot(1);
        p2GhostX = []; p2GhostY = []; p2GhostSeq = []; p2GhostDeaths = 0;
        falls2 = 0;
    }

    function joinP2() {
        if (p2Joined) return;
        p2Joined = true;
        resetP2();
        // Snap P2's camera to its own half-width pane (no glide from camX1/camY1).
        camX2 = camTargetXFor(1);
        camY2 = camTargetYFor(1);
    }

    function leaveP2() {
        if (!p2Joined) return;
        p2Joined = false;
        p2done = false;
        p2Vx = 0; p2JumpHeld = false; p2JumpWas = false; p2Gliding = false;
        camX2 = camX1;
        camY2 = camY1;
    }

    function toggleP2() {
        if (p2Joined) leaveP2();
        else joinP2();
    }

    // ---- finish orb ----
    function _placeOrb() {
        // centre of the summit platform, floating orbHover above its surface
        var last = platforms.length > 0 ? platforms[platforms.length - 1] : null;
        orbX = last ? last.x + last.w / 2 : baseW / 2;
        orbY = last ? last.y - orbHover : 0;
        orbTaken = false;
        orbWinner = -1;
    }

    // Glyph Hunt pickup: the glyph is worth a point to the player whose colour it
    // carries, and kills the player it does not belong to. Reaching the target
    // ends the round with the same win path as the orb.
    function _hazCollect(idx, slot) {
        var mine = hazTeam[slot] === idx;
        if (!mine) {
            // The other player's colour is a body hit, not a bad catch: the same
            // thud as shoving the other glyph (onCrushed -> "bump"), and a death on
            // the spot — ghost marker where it happened, back to platform 0, fall
            // counted, exactly like a rock.
            collected(idx, false);
            _crush(idx);
            return;
        }
        if (idx === 0) p1Score++; else p2Score++;
        collected(idx, true);
        var target = Modes.get(modeId).hazard.target || 0;
        if (target > 0 && (idx === 0 ? p1Score : p2Score) >= target)
            declareWin(idx, elapsed);
    }

    function _stepOrb() {
        if (!roundActive || orbTaken || !orbActive) return;
        for (var idx = 0; idx < (p2Joined ? 2 : 1); idx++) {
            // painted body, not the collision box: see paintedH above
            var pcx = (idx === 0 ? p1x : p2x) + playerW / 2;
            var pcy = (idx === 0 ? p1y : p2y) + playerH - paintedH / 2;
            if (Math.abs(orbX - pcx) <= orbRNow + sideBodyW / 2
                    && Math.abs(orbY - pcy) <= orbRNow + paintedH / 2) {
                _collectOrb(idx);
                return;
            }
        }
    }

    function _collectOrb(idx) {
        if (orbTaken || !roundActive) return;
        orbTaken = true;
        orbWinner = idx;
        orbCollected(idx);        // view: shrink the orb, grow + light the glyph, cue
        declareWin(idx, elapsed); // the clock stops at the touch, not at landing
    }

    // One physics tick. Inputs must be set (p1Vx/p1JumpHeld/...) beforehand.
    function tick(dt) {
        // Cameras keep running while idle so the split panes frame the spawn
        // platforms before the round starts (and after P2 joins mid-overlay).
        if (!roundActive) { _updateCam(dt); return; }
        if (paused) return;      // frozen: no sim step, no camera drift, no clock
        elapsed = (Date.now() - startStamp) / 1000;
        orbSizePulse = 0.5 - 0.5 * Math.cos(elapsed * 2.0);
        orbBrightPulse = 0.5 - 0.5 * Math.cos(elapsed * 4.0);
        _stepPlayer(0, dt);
        if (p2Joined) {
            _stepPlayer(1, dt);
            _separateSide(dt);      // players are solid to each other sideways
            _carryRiders(dt);       // …and the head is a platform
        }
        _stepHazards(dt);       // rocks fall and may crush a player…
        _stepOrb();             // …and the summit's orb ends the round on touch
        _updateCam(dt);         // …so the camera update comes after the respawn
        var m = Modes.get(modeId);
        if (m.onTick) m.onTick(engine);
    }

    function declareWin(idx, timeSec) {
        if (!roundActive || winner !== "") return;
        winTime = timeSec;
        winner = idx === 0 ? "Player 1 (Ö)" : "Player 2 (Ö)";
        winnerGlyph = "Ö";
        if (idx === 0) p1done = true; else p2done = true;
        roundActive = false;
        var m = Modes.get(modeId);
        if (m.tracksBest) {
            var ms = Math.round(timeSec * 1000);
            var cur = bestFor(modeId);
            if (cur < 0 || ms < cur) {
                var b = bestByMode;
                b[modeId] = ms;
                bestByMode = b; // reassign so bindings/signals notice
            }
        }
        roundEnded(idx, timeSec);
    }

    function _boost(vy, strength) {
        // Never cancel a stronger rise; only boost when weaker/falling.
        return vy > strength ? strength : vy;
    }

    // ---- player-on-player collision ----
    // Horizontal contact uses the *painted* glyph span, never the 20-unit
    // collision box: the box has invisible corners that would otherwise hold a
    // rider in mid-air diagonally above the other player. Both bodies are the
    // same width, so comparing the box left edges compares the glyph centres.
    function _bodiesOverlap(ax, bx) {
        return Math.abs(ax - bx) <= sideBodyW;
    }

    // True if idx's feet are resting on the other player's head: horizontal
    // overlap (same forgiving test as platforms) and the feet within a small
    // band around the carrier's top edge. The band grows with the carrier's
    // upward speed so a rising carrier lifts the rider instead of leaving them
    // inside, and a rising *rider* is never captured (they can jump off).
    function _carriedByOther(idx, dt) {
        if (!p2Joined) return false;
        var isP1 = idx === 0;
        var x = isP1 ? p1x : p2x;
        var y = isP1 ? p1y : p2y;
        var vy = isP1 ? p1vy : p2vy;
        var ox = isP1 ? p2x : p1x;
        var oy = isP1 ? p2y : p1y;
        var ovy = isP1 ? p2vy : p1vy;
        if (vy < -1) return false;                       // rider is rising
        if (!_bodiesOverlap(x, ox)) return false;
        var feet = y + playerH;
        var lift = Math.max(0, -ovy) * dt;               // carrier rising this tick
        return feet >= oy - 6 && feet <= oy + 8 + lift;
    }

    // Keep riders glued to the carrier's head while the carrier walks or jumps.
    function _carryRiders(dt) {
        p1OnHead = _carriedByOther(0, dt);
        p2OnHead = _carriedByOther(1, dt);
        if (p1OnHead) {
            p1y = p2y - playerH; p1vy = 0; p1ground = true; p1Jumps = 0;
        }
        if (p2OnHead) {
            p2y = p1y - playerH; p2vy = 0; p2ground = true; p2Jumps = 0;
        }
    }

    // Players are solid sideways: overlapping bodies are pushed apart (half
    // each), so walking into the other player shoves them instead of passing
    // through. Only a real side hit counts — boxes that merely touch vertically
    // (a rider standing on a head) are left to _carryRiders.
    function _separateSide(dt) {
        // One hit per contact: edge-detected, then a cooldown, so two players
        // leaning on each other keep being pushed apart but the thud fires once.
        hitCd = Math.max(0, hitCd - dt);
        var overlapY = Math.min(p1y + playerH, p2y + playerH) - Math.max(p1y, p2y);
        var overlapX = sideBodyW - Math.abs(p1x - p2x);
        var touching = overlapY > sideTouch && overlapX > 0;
        if (touching && !sideTouching && hitCd <= 0) {
            hitCd = hitCooldown;
            bumped();
        }
        sideTouching = touching;
        if (!touching) return;
        var push = overlapX / 2;
        var dir = p1x <= p2x ? -1 : 1;
        p1x = _clampX(p1x + dir * push);
        p2x = _clampX(p2x - dir * push);
    }

    // Record where a player dropped off the tower: fill the next ring slot
    // (reusing the oldest once ghostMax deaths have happened) and let the view
    // re-read the slots. `x` is the dead glyph's centre and `y` the world y of
    // its feet (see p1GhostX/p1GhostY).
    function _addGhost(idx, x, y) {
        var deaths = idx === 0 ? p1GhostDeaths : p2GhostDeaths;
        var slot = deaths % ghostMax;
        var xs = (idx === 0 ? p1GhostX : p2GhostX).slice();
        var ys = (idx === 0 ? p1GhostY : p2GhostY).slice();
        var seqs = (idx === 0 ? p1GhostSeq : p2GhostSeq).slice();
        xs[slot] = x;             // no rounding: halves of a unit are what the eye reads as 'the same spot'
        ys[slot] = y;
        seqs[slot] = deaths;
        if (idx === 0) {
            p1GhostX = xs; p1GhostY = ys; p1GhostSeq = seqs; p1GhostDeaths = deaths + 1;
        } else {
            p2GhostX = xs; p2GhostY = ys; p2GhostSeq = seqs; p2GhostDeaths = deaths + 1;
        }
    }

    // ---- hazards: spawn, fall, hit (Asterisk Attack) ----
    // The generator is the same small LCG Course.js uses, seeded from the round
    // seed, so a round's rock pattern is reproducible instead of Math.random.
    function _hazRand() {
        // Math.imul keeps the 32-bit product exact; >>> 0 makes it unsigned
        hazSeed = ((hazSeed * 1664525 + 1013904223) >>> 0);
        return hazSeed / 4294967296;
    }

    // How far the leader has climbed, 0..1: drives the spawn rate and the fall
    // speed, so the tower gets meaner the higher you get.
    function _hazLead() {
        var top = p2Joined ? Math.max(p1Plat, p2Plat) : p1Plat;
        return platCount > 1 ? top / (platCount - 1) : 0;
    }

    // Rocks enter above the *higher* pane, so whoever is ahead always sees them
    // come in off the top edge; the other player meets them on the way up.
    function _hazSkyY() {
        var top = (p2Joined && camY2 < camY1) ? camY2 : camY1;
        return top - 24;
    }

    // One glyph of a given size class, stamped for one player. Split out of
    // _spawnHazard so the collect modes can drop a matched *pair* per gap.
    function _emitHazard(cfg, sz, team) {
        var slot = hazNext;
        var half = cfg.sizes[sz] / 2;
        var xs = hazX.slice(), ys = hazY.slice(), ss = hazSize.slice(), as = hazAng.slice();
        xs[slot] = half + _hazRand() * (baseW - 2 * half);   // inside the arena
        ys[slot] = _hazSkyY() - half;
        ss[slot] = sz;
        var ts = hazTeam.slice();
        ts[slot] = team;
        hazTeam = ts;
        // diagonal from the first tick: |angle| in [angleMin, angleMax], either
        // direction, so no glyph ever comes straight down
        var deg = cfg.angleMin + _hazRand() * Math.max(0, cfg.angleMax - cfg.angleMin);
        var rad = deg * Math.PI / 180;
        as[slot] = _hazRand() < 0.5 ? -rad : rad;
        hazX = xs; hazY = ys; hazSize = ss; hazAng = as;
        hazNext = (slot + 1) % hazardMax;
    }

    function _spawnHazard(cfg) {
        var sz = Math.floor(_hazRand() * cfg.sizes.length);
        if (sz > cfg.sizes.length - 1) sz = cfg.sizes.length - 1;
        // Collect modes spawn a matched PAIR per gap: one glyph in each player's
        // colour at the same size class, at independent positions. Both players
        // then get the same offer — the fairness rule this mode is built on — and
        // solo play keeps the single glyph, which is always player 1's.
        _emitHazard(cfg, sz, 0);
        if (cfg.teams && p2Joined) _emitHazard(cfg, sz, 1);
        hazTimer = 0;
        // rate ramps with the leader (gapMin at the top) and jitters ±25 %, so
        // the barrage stays "here and there" instead of metronomic
        var gap = cfg.gapMin + (cfg.gapMax - cfg.gapMin) * (1 - _hazLead());
        hazGap = gap * (0.75 + 0.5 * _hazRand());
    }

    function _stepHazards(dt) {
        var cfg = Modes.get(modeId).hazard;
        if (!cfg) {
            if (hazSize.length > 0) clearHazards();
            return;
        }
        var speed = cfg.fallSpeed + cfg.speedRamp * _hazLead();
        // Free a rock once it is past the bottom of the lowest pane (and past
        // the arena floor line, which is as low as anything can be needed).
        var camLow = (p2Joined && camY2 > camY1) ? camY2 : camY1;
        var floorWorld = Math.max(baseH, camLow + baseH);

        var xs = hazX.slice(), ys = hazY.slice();
        var ss = hazSize, as = hazAng;
        var dropped = false, bounced = false;
        for (var s = 0; s < hazardMax; s++) {
            var sz = hazardSizeAt(s);
            if (sz < 0) continue;
            var half = cfg.sizes[sz] / 2;
            var ang = as[s] === undefined ? 0 : as[s];
            var ny = ys[s] + speed * Math.cos(ang) * dt;
            if (ny - half > floorWorld) {
                if (!dropped) { ss = ss.slice(); dropped = true; }
                ss[s] = -1;
                continue;
            }
            // the slide keeps its angle: mirror it at the arena walls so a rock
            // can never drift out of the tower (the barrage stays dense)
            var nx = xs[s] + speed * Math.sin(ang) * dt;
            if (nx - half < 0) {
                nx = half;
                if (!bounced) { as = as.slice(); bounced = true; }
                as[s] = -ang;
            } else if (nx + half > baseW) {
                nx = baseW - half;
                if (!bounced) { as = as.slice(); bounced = true; }
                as[s] = -ang;
            }
            xs[s] = nx;
            ys[s] = ny;
        }
        hazX = xs; hazY = ys;        // the view re-reads the pool every tick
        if (dropped) hazSize = ss;
        if (bounced) hazAng = as;

        hazTimer += dt;
        if (hazTimer >= hazGap) _spawnHazard(cfg);

        _stepPowerups(dt);
        _hazHits(cfg);
    }

    // Above a given player's own pane: where their power-up enters the sky.
    function _skyYFor(idx) {
        var cam = idx === 0 ? camY1 : (p2Joined ? camY2 : camY1);
        return cam - 24;
    }

    // Release, fall and catch. The drop is owner-bound: only the player it was
    // released for can take it, so a shared arena stays fair.
    function _stepPowerups(dt) {
        var cfg = Modes.get(modeId).hazard;
        if (!cfg || cfg.powerupPlat === undefined) {
            if (powLive[0] || powLive[1] || pow50[0] || pow50[1]) clearPowerups();
            return;
        }
        var take = pow50.slice();
        var live = powLive.slice();
        var ys = powY.slice();
        var xs = powX.slice();
        var call = (p2Joined && camY2 > camY1) ? camY2 : camY1;
        var floorWorld = Math.max(baseH, call + baseH);
        var n = p2Joined ? 2 : 1, changed = false;

        for (var idx = 0; idx < n; idx++) {
            if (!take[idx] && !boldFor(idx)
                    && (idx === 0 ? p1Plat : p2Plat) >= cfg.powerupPlat) {
                take[idx] = true;
                live[idx] = true;
                xs[idx] = baseW / 2;                 // down the arena's middle
                ys[idx] = _skyYFor(idx) - playerH / 2;
                changed = true;
            }
            if (!live[idx]) continue;
            var ny = ys[idx] + powFall * dt;
            ys[idx] = ny;
            changed = true;
            var pcx = (idx === 0 ? p1x : p2x) + playerW / 2;
            var pcy = (idx === 0 ? p1y : p2y) + playerH / 2;
            if (Math.abs(xs[idx] - pcx) <= sideBodyW && Math.abs(ny - pcy) <= playerH) {
                live[idx] = false;
                if (idx === 0) p1Bold = true; else p2Bold = true;
                powered(idx);
                continue;
            }
            if (ny - playerH / 2 > floorWorld) live[idx] = false;   // missed
        }
        if (changed) { pow50 = take; powLive = live; powY = ys; powX = xs; }
    }

    // A rock overlapping the *painted* body (not the invisible collision box,
    // same rule as player-vs-player) crushes the player: the rock is spent, the
    // player leaves a marker where they stood and restarts from platform 0.
    function _hazHits(cfg) {
        var ss = hazSize.slice();
        var spent = false;
        for (var idx = 0; idx < (p2Joined ? 2 : 1); idx++) {
            var pcx = (idx === 0 ? p1x : p2x) + playerW / 2;
            var pcy = (idx === 0 ? p1y : p2y) + playerH / 2;
            for (var s = 0; s < hazardMax; s++) {
                var sz = ss[s] === undefined ? -1 : ss[s];
                if (sz < 0) continue;
                var half = cfg.sizes[sz] / 2;
                if (Math.abs(hazX[s] - pcx) <= half + sideBodyW / 2
                        && Math.abs(hazY[s] - pcy) <= half + playerH / 2) {
                    ss[s] = -1;
                    spent = true;
                    if (cfg.teams) {
                        _hazCollect(idx, s);
                        break;          // one glyph per player per tick
                    }
                    if (boldFor(idx)) {
                        // charged: the rock is absorbed. The charge is spent, so
                        // the glyph drops back to its normal look…
                        if (idx === 0) p1Bold = false; else p2Bold = false;
                        shielded(idx);
                    } else {
                        _crush(idx);        // …without a charge it is a death
                    }
                    break;              // one rock per player per tick
                }
            }
        }
        if (spent) hazSize = ss;
    }

    // Death by hazard: marker at the death spot (its feet, so the glyph sits
    // exactly where the player stood), count the death and restart from the
    // spawn — the same consequence as a fall, minus the trip down.
    function _crush(idx) {
        var isP1 = idx === 0;
        _addGhost(idx, (isP1 ? p1x : p2x) + playerW / 2, (isP1 ? p1y : p2y) + playerH);
        crushed(idx);
        var spot = _startSpot(idx);
        if (isP1) {
            p1x = spot.x; p1y = spot.y; p1vy = 0; p1ground = true; p1Jumps = 0;
            falls1++; p1Plat = 0; p1done = false;
        } else {
            p2x = spot.x; p2y = spot.y; p2vy = 0; p2ground = true; p2Jumps = 0;
            falls2++; p2Plat = 0; p2done = false;
        }
        _rewardDeath(idx);
        var m = Modes.get(modeId);
        if (m.onFall && m.onFall(engine, idx)) {
            // mode may end the round on a death (future modes)
            roundActive = false;
            roundEnded(idx, elapsed);
        }
    }

    // Where a respawn puts a player: platform 0, at the same offsets the round
    // start uses. Shared by the fall path and by a hazard death.
    function _startSpot(idx) {
        var plats = platforms;
        var s = plats.length > 0 ? plats[0] : { x: 60, y: platBaseY, w: 120 };
        return idx === 0 ? { x: s.x + 18, y: s.y - playerH }
                         : { x: s.x + s.w - 32, y: s.y - playerH };
    }

    function _clampX(x) {
        if (x < 6) return 6;
        if (x > baseW - playerW) return baseW - playerW;
        return x;
    }

    // World y a camera should show at the top edge of player idx's viewport.
    // Panes are always full height (solo = whole board, split = 220x500 sides),
    // so the top edge never goes below the arena floor.
    function camTargetYFor(idx) {
        var t = (idx === 0 ? p1y : p2y) - baseH * camLead;
        return t > 0 ? 0 : t;
    }

    // World x a camera should show at the left edge of player idx's viewport:
    // the player stays centered in its pane, clamped to the arena sides.
    function camTargetXFor(idx) {
        var vw = viewportW;
        var maxLeft = baseW - vw;
        var t = (idx === 0 ? p1x : p2x) + playerW / 2 - vw / 2;
        if (t < 0) return 0;
        return t > maxLeft ? maxLeft : t;
    }

    function _updateCam(dt) {
        var k = Math.min(1.0, dt * 10);
        camX1 += (camTargetXFor(0) - camX1) * k;
        camY1 += (camTargetYFor(0) - camY1) * k;
        if (p2Joined) {
            camX2 += (camTargetXFor(1) - camX2) * k;
            camY2 += (camTargetYFor(1) - camY2) * k;
        } else {
            camX2 = camX1;   // idle camera stays parked with P1's
            camY2 = camY1;
        }
    }

    function _stepPlayer(idx, dt) {
        var isP1 = idx === 0;
        var x = isP1 ? p1x : p2x;
        var y = isP1 ? p1y : p2y;
        var vy = isP1 ? p1vy : p2vy;
        var ground = isP1 ? p1ground : p2ground;
        var vx = isP1 ? p1Vx : p2Vx;
        var jump = isP1 ? p1JumpHeld : p2JumpHeld;
        var jumps = isP1 ? p1Jumps : p2Jumps;
        var was = isP1 ? p1JumpWas : p2JumpWas;
        var wasGround = isP1 ? p1ground : p2ground;   // grounded before this tick
        var pressed = jump && !was;

        x = _clampX(x + vx * moveSpeed * dt);

        if (pressed) {
            if (ground) {
                vy = jumpVel;
                ground = false;
                jumps = 1;
                jumped(idx);
            } else if (jumps < 2) {
                var v2 = jumpVel * Math.sqrt(doubleJumpHeightMult);
                vy = _boost(vy, v2);
                jumps = 2;
                jumped(idx);
            }
        }
        // Glide: holding jump while falling (after at least one jump) softens
        // gravity and caps the descent speed.
        var gliding = jumps >= 1 && !ground && vy > 0 && jump;
        vy += gravity * (gliding ? glideGravityMult : 1.0) * dt;
        if (gliding && vy > glideFall) vy = glideFall;
        if (vy > maxFall) vy = maxFall;
        var prevFeet = y + playerH;
        y += vy * dt;
        var feet = y + playerH;
        ground = false;

        var plats = platforms;
        if (vy >= 0) {
            for (var i = 0; i < plats.length; i++) {
                var p = plats[i];
                var top = p.y;
                if (prevFeet <= top + 5 && feet >= top - 4
                        && x + 12 >= p.x - 6 && x + 2 <= p.x + p.w + 6) {
                    y = top - playerH;
                    vy = 0;
                    ground = true;
                    jumps = 0;
                    if (isP1) p1Plat = i; else p2Plat = i;
                    // only a real impact: a resting glyph re-enters this branch
                    // every tick (its feet are re-snapped)
                    if (!wasGround) landed(idx, x, p.x, p.w, top, p.glyph);
                    // no win here: the summit is only the orb's pedestal, the
                    // orb contact in _stepOrb() is the end of the round
                    var m = Modes.get(modeId);
                    if (m.onLand) m.onLand(engine, idx, i);
                    break;
                }
            }
        }
        // player-on-player: land on the other glyph's head exactly like on a
        // platform, so a rider can stand on the carrier and jump off again
        if (!ground && vy >= 0 && p2Joined) {
            var oy2 = isP1 ? p2y : p1y;
            var ox2 = isP1 ? p2x : p1x;
            if (prevFeet <= oy2 + 5 && feet >= oy2 - 4
                    && _bodiesOverlap(x, ox2)) {
                y = oy2 - playerH;
                vy = 0;
                ground = true;
                jumps = 0;
            }
        }
        // Crossed the arena floor line: the ghost row is anchored on that same
        // line, so the marker is placed here — the exact spot the fall left the
        // arena. Recording it later (in the reset below, 30 units further down)
        // let the sideways steer of those extra ticks offset the marker.
        if (roundActive && prevFeet <= baseH && feet > baseH)
            _addGhost(isP1 ? 0 : 1, x + playerW / 2, ghostY);   // the floor line

        if (roundActive && y > baseH + 30) {
            // Fell off the bottom of the tower: back to platform 0 (full
            // progress reset), count the fall.
            var sp = _startSpot(idx);
            x = sp.x; y = sp.y;
            vy = 0; ground = true;
            jumps = 0;
            if (isP1) { falls1++; p1Plat = 0; } else { falls2++; p2Plat = 0; }
            if (isP1) p1done = false; else p2done = false;
            _rewardDeath(idx);
            var m2 = Modes.get(modeId);
            if (m2.onFall && m2.onFall(engine, idx)) {
                // mode may end the round on a fall (future modes)
                roundActive = false;
                roundEnded(idx, elapsed);
            }
        }
        var airGlide = gliding && !ground && vy > 0;
        // Footstep cadence: only while walking along a floor — a player pinned
        // against the arena edge still counts, since the velocity is set even
        // when a wall stops the movement. Stopping resets the timer, so the next
        // walk steps immediately.
        var stepT = isP1 ? p1StepT : p2StepT;
        if (ground && vx !== 0) {
            stepT -= dt;
            if (stepT <= 0) {
                stepT = stepInterval;
                stepped(idx);
            }
        } else {
            stepT = 0;
        }
        // Idle seconds: standing still on a floor with nothing asked of it. Any
        // intent (walk, jump, glide), a fall or a fresh round resets it; the view
        // sleeps the glyph after view.idleSeconds of it.
        var idle = isP1 ? p1Idle : p2Idle;
        idle = (ground && vx === 0 && !jump && !airGlide) ? idle + dt : 0;
        if (isP1) {
            p1x = x; p1y = y; p1vy = vy; p1ground = ground; p1Jumps = jumps;
            p1JumpWas = jump; p1Gliding = airGlide; p1StepT = stepT; p1Idle = idle;
        } else {
            p2x = x; p2y = y; p2vy = vy; p2ground = ground; p2Jumps = jumps;
            p2JumpWas = jump; p2Gliding = airGlide; p2StepT = stepT; p2Idle = idle;
        }
    }

    Component.onCompleted: {
        // a restore can hand us a mode id this build no longer has (renamed or
        // dropped): snap back before the first round is built
        if (!Modes.isReady(modeId)) modeId = "race";
        startRound();
        roundActive = false; // show ready overlay first
    }
}
