// Ojumpy game modes — rules registry.
//
// A mode is a plain object; the engine (GameEngine.qml) drives the shared
// simulation and delegates mode-specific rules to these hooks. `ready: false`
// shows in mode select but cannot be started.
//
// Hook contract:
//   tagGlyph                                  label for the pane HUD (goal marker)
//   onLand(engine, playerIdx, platIdx) -> void landing hook
//   onFall(engine, playerIdx)        -> bool   true declares a loss/end
//   onTick(engine)                   -> void   called every physics tick
//
// The engine guarantees, whenever a hook runs:
//   engine.roundActive, engine.elapsed, engine.falls1/2, engine.p1*/p2*,
//   engine.platforms (base-unit layout), engine.playerH

var RACE = {
    id: "race",
    name: "Race to 100",
    tagline: "First glyph to the summit orb wins — climb to 100 and jump into it",
    tagGlyph: "",
    ready: true,
    tracksBest: true, // best clear time is kept per mode
    goalIndex: 100,
    onFall: function () { return false; },
    onTick: function () {}
};

// --- Asterisk Attack -------------------------------------------------------
// The engine runs the hazard pool off this entry's `hazard` block; a mode
// without one is a plain climb. "*" rocks drop at a random x in three sizes
// whose colours are the platform size classes. A hit is a death: the player
// restarts from platform 0 and leaves a marker where they stood.
//
// Tunables (base units, seconds):
//   sizes     world width of size class 0/1/2, small/mid/large
//   gapMin/Max  seconds between rocks at full progress / at the start
//   angleMin/Max  degrees off vertical, never 0; rocks bounce off the arena
//               walls instead of leaving the tower
//   fallSpeed   base descent speed, speedRamp adds this much at full progress
//   powerupPlat  platform that releases the bold "O", one per player, falling
//               down the arena's middle; a catch survives one rock hit
//   powerupDeaths  every N deaths also drops one at the start, right onto the
//               respawning player
var ASTERISKS = {
    id: "asterisks",
    name: "Asterisk Attack",
    tagline: "Dodge the sliding * to 100, grab the bold O at 50, jump into the orb",
    tagGlyph: "",
    ready: true,
    tracksBest: true,
    goalIndex: 100,
    hazard: {
        glyph: "*",
        sizes: [8, 14, 20],
        gapMin: 0.18,
        gapMax: 0.55,
        angleMin: 8,       // never 0: every rock flies diagonal
        angleMax: 30,
        fallSpeed: 150,
        speedRamp: 110,
        powerupPlat: 50,
        powerupDeaths: 5
    },
    onFall: function () { return false; },
    onTick: function () {}
};

// --- Glyph Hunt ------------------------------------------------------------
// Every gap drops a matched pair: the same size class in each player's own
// colour, at independent positions, and a drop is in one colour only. Touching
// yours scores, touching theirs is a body shove (the same bump cue) that kills
// on the spot, leaves a ghost marker and sends the player back to platform 0.
//
// The pair drops whether or not player 2 has joined, so solo play gets both
// colours too: the second one is pure handicap, a hazard to read and dodge for a
// round with nobody to compete against.
//
// Tunables (base units, seconds), the rock knobs plus:
//   glyphs    one character per size class (small, middle, large)
//   points    what one catch of each size class is worth
//   teams     true = colour each drop for one player and score on touch
//   target    points needed to win
var GLYPHS = {
    id: "glyphhunt",
    name: "Glyph Hunt",
    tagline: "Reach 100 points: $ 3 · & 2 · # 1 — the other colour kills",
    tagGlyph: "$",                  // the richest catch: the small size class
    ready: true,
    tracksBest: true,
    goalIndex: 100,
    orb: false,                     // no summit orb in this mode
    hazard: {
        glyph: "$",                 // fallback for a class without its own char
        glyphs: ["$", "&", "#"],
        points: [3, 2, 1],
        sizes: [8, 14, 20],
        gapMin: 0.35,
        gapMax: 0.9,
        angleMin: 8,
        angleMax: 30,
        fallSpeed: 150,
        speedRamp: 110,
        teams: true,
        target: 100
    },
    onLand: function () { return false; },
    onFall: function () { return false; },
    onTick: function () {}
};

// --- Match or Fall: your colour is the platform's colour ----------------------
// The same climb and the same summit orb as Race to 100, with every climbing
// platform tagged 0 or 1: tag 0 is player 1's colour, tag 1 player 2's. A
// platform only holds the player whose colour it carries, so the other colour
// falls straight through it, and each player picks their colour with the switch
// key (E, or the pad's X in the reference game; here LB for player 1 and RB for
// player 2, because this plugin already spends B and X on player 2's jump).
//
// The tags are assigned in equal halves and shuffled, the same fair assignment
// the reference game uses: a plain coin flip per platform would let one colour
// run away with the long stretches. The start pad and the summit band carry no
// tag and are always solid, so there is always a safe spawn and a reachable orb.
//
// Switching while you stand on a platform drops you through it, which is the
// whole risk of the mode.
var MATCHFALL = {
    id: "matchfall",
    name: "Match or Fall",
    tagline: "Climb to 100 on platforms of your colour — E switches you to the other one",
    tagGlyph: "~",
    ready: true,
    tracksBest: true,
    goalIndex: 100,
    matchFall: true,      // platforms are colour-tagged; only your colour holds
    onFall: function () { return false; },
    onTick: function () {}
};

var FALLS = {
    id: "fallgauntlet",
    name: "Fall Gauntlet",
    tagline: "Reach the top; fewest falls wins",
    ready: false,
    tracksBest: false,
    onLand: function () { return false; },
    onFall: function (engine, playerIdx) {
        // future rule: first to N falls is eliminated
        return false;
    },
    onTick: function () {}
};

var ALL = [RACE, ASTERISKS, GLYPHS, MATCHFALL, FALLS];

function list() {
    return ALL;
}

// The entry with this id, or null when this build does not have it. This is also
// the validator: `get()` falls back to RACE, and RACE is ready, so a stale id
// asked about readiness would answer yes.
function find(id) {
    for (var i = 0; i < ALL.length; i++)
        if (ALL[i].id === id) return ALL[i];
    return null;
}

// Safe lookup for the simulation: an unknown id plays as Race to 100 rather
// than crashing a round.
function get(id) {
    return find(id) || RACE;
}

function isReady(id) {
    var m = find(id);
    return !!m && m.ready === true;
}
