// Ojumpy game modes — rules registry.
//
// A mode is a plain object; the engine (GameEngine.qml) drives the shared
// simulation (movement, gravity, platform landings, falls) and delegates
// mode-specific rules to the hooks below. Adding a multiplayer mode = add an
// entry here + implement its hooks. `ready: false` modes show in the mode
// select screen but can't be started yet.
//
// Hook contract:
//   tagGlyph                                   label for the pane HUD (goal marker)
//   onLand(engine, playerIdx, platIdx) -> void   landing hook (no mode ends here
//                                                any more: the summit's orb does,
//                                                see GameEngine._stepOrb)
//   onFall(engine, playerIdx)          -> bool   return true to declare a loss/end
//   onTick(engine)                     -> void   called every physics tick
//
// The engine guarantees, whenever a hook runs:
//   engine.roundActive, engine.elapsed, engine.falls1/2, engine.p1*/p2*,
//   engine.platforms (base-unit layout), engine.playerH

var RACE = {
    id: "race",
    name: "Race to 100",
    tagline: "First glyph to the summit orb wins — climb to 100 and jump into it",
    // what the pane tag shows as the goal marker in front of the progress
    // (the start pad's own character, so the tag reads as "the climb")
    tagGlyph: "~",
    ready: true,
    tracksBest: true, // best clear time is kept per mode
    goalIndex: 100,
    onFall: function () { return false; },
    onTick: function () {}
};

// --- Asterisk Attack: the same climb, under a glyph bombardment ---------------
// The engine runs the hazard pool off this entry's `hazard` block (a mode
// without one is a plain climb): "*" rocks drop in at a random x, in three
// sizes whose colours are the platform size classes. A hit is a death — the
// player restarts from platform 0 and leaves a marker where they stood.
//
// Tunables (base units, seconds):
//   sizes     world width of size class 0/1/2 (small/mid/large)
//   gapMin/Max  seconds between rocks at full progress / at the start
//   angleMin/Max  degrees off vertical: every rock flies diagonal, and it
//               bounces off the arena walls instead of leaving the tower
//   fallSpeed   base descent speed, speedRamp adds this much at full progress
//   powerupPlat  platform that releases the bold "O" (one per player, it falls
//               down the arena's middle; catch it to survive one rock hit)
//   powerupDeaths  every N deaths also drops one at the start, right onto the
//               respawning player (5, 10, 15 … — a way back into a bad round)
var ASTERISKS = {
    id: "asterisks",
    name: "Asterisk Attack",
    tagline: "Dodge the sliding * to 100, grab the bold O at 50, jump into the orb",
    tagGlyph: "~",
    ready: true,
    tracksBest: true,
    goalIndex: 100,
    hazard: {
        glyph: "*",
        sizes: [8, 14, 20],
        gapMin: 0.18,      // a third of the first cut's gap = three times the rocks
        gapMax: 0.55,
        angleMin: 8,       // never straight down: the sky is always slanted
        angleMax: 30,
        fallSpeed: 150,
        speedRamp: 110,
        powerupPlat: 50,
        powerupDeaths: 5
    },
    onFall: function () { return false; },
    onTick: function () {}
};

// --- Glyph Hunt: catch your own colour ---------------------------------------
// The same sky as Asterisk Attack — diagonal glyphs in three size classes, one
// glyph per gap, bouncing off the arena walls — and the glyphs *are* the score.
// Every gap drops a matched pair: both players get the same size class in their
// own colour, at independent positions, so neither is ever offered a worse round
// than the other. Take yours: +1 point and a bing. Touch theirs: it hits like a
// body shove (the same bump cue) and kills you on the spot — ghost marker where
// it happened, back to platform 0. First to `target` wins.
//
// Tunables (base units, seconds) — the rock knobs, plus:
//   glyphs    one character per size class (small, middle, large)
//   teams     true = colour each drop for one player and score on touch
//   target    points needed to win
// In solo play every glyph is player 1's, so the mode still works alone.
var GLYPHS = {
    id: "glyphhunt",
    name: "Glyph Hunt",
    tagline: "Catch 10 glyphs of your own colour — the other player's kills",
    tagGlyph: "$",                  // the biggest kind of prey
    ready: true,
    tracksBest: true,
    goalIndex: 100,
    orb: false,                     // no summit orb here: the glyphs are the goal
    hazard: {
        glyph: "$",                 // the size-2 character (single-glyph modes use it)
        glyphs: ["§", "#", "$"],    // size classes: small, middle, large
        sizes: [8, 14, 20],
        // calmer than Asterisk Attack on purpose: there the sky is a hazard to
        // dodge, here it is the thing you have to intercept
        gapMin: 0.35,
        gapMax: 0.9,
        angleMin: 8,
        angleMax: 30,
        fallSpeed: 150,
        speedRamp: 110,
        teams: true,          // matched pairs + colour-gated pickups
        target: 10
    },
    onLand: function () { return false; },
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

var ALL = [RACE, ASTERISKS, GLYPHS, FALLS];

function list() {
    return ALL;
}

// The entry with this id, or null when this build does not have it. Validating
// an id (a restored document, the engine's mode guard) MUST come through here:
// `get()` below falls back to RACE, so asking it whether a stale id is "ready"
// used to answer yes — the fallback mode is ready.
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
