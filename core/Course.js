// The tower's course generator, as pure functions.
//
// `build(config, seed)` depends on the tuning config and the round seed only,
// with no engine state, so one seed always produces the same course.
//
// Steps climb by one discrete unit:
//   single : +1 unit (normal jump)   double : +2 units (needs the double jump)
//   bridge : ±0 units (long flat crossing)
// Horizontal spread is a self-avoiding walk with a heading: it keeps its
// direction, bounces off the arena sides, shrinks the gap before giving up, and
// validates each candidate. Widths come from a three-size pool, never the same
// size twice.
.pragma library

// Linear congruential generator. Must stay identical to the engine's, or a
// seed would not reproduce a course.
function rand(seedObj) {
    seedObj.s = (seedObj.s * 1664525 + 1013904223) >>> 0;
    return seedObj.s / 4294967296;
}

// Weighted step kind, mostly single jumps.
function pickKind(r) {
    var roll = rand(r);
    if (roll < 0.55) return "single";
    if (roll < 0.78) return "double";
    return "bridge";
}

// Art for a platform of this size class (small/middle/long).
function glyphForSize(cfg, w) {
    if (w <= cfg.platSizes[0]) return cfg.glyphs[1];
    if (w >= cfg.platSizes[cfg.platSizes.length - 1]) return cfg.glyphs[3];
    return cfg.glyphs[2];
}

// True if (x..x+w) at height y would touch an already placed platform on the
// same level. Platforms on other levels may share the footprint.
function sameLevelHit(cfg, list, x, w, y) {
    for (var i = 0; i < list.length; i++) {
        var p = list[i];
        if (Math.abs(p.y - y) < cfg.climbUnit * 0.5
                && x < p.x + p.w + cfg.genMinGap && p.x < x + w + cfg.genMinGap) {
            return true;
        }
    }
    return false;
}

// Self-avoiding walk. Returns null when it boxes itself in; the caller retries
// with a fresh seed. Each platform is one jump up, so reachability holds.
function grow(cfg, r) {
    var list = [{
        x: cfg.basePlatX, y: cfg.platBaseY, w: cfg.basePlatW,
        glyph: cfg.glyphs[0], edge: true, idx: 0, kind: "base", sizeClass: 0 - 1
    }];
    var heading = rand(r) < 0.5 ? 1 : -1;
    var prevKind = "base";
    var prevSize = 0;
    for (var i = 1; i < cfg.platCount; i++) {
        var isGoal = i === cfg.platCount - 1;
        var kind = i === 1 ? "single" : pickKind(r);
        if (kind === "bridge" && prevKind === "bridge") kind = "single";
        // The finish is always a climbing step: a flat step would put the taller
        // checkered band level with the last platform, second row below it.
        if (isGoal && kind !== "double") kind = "single";
        var prev = list[i - 1];

        // size pool, never the same size twice in a row
        var sizes = [];
        for (var s = 0; s < cfg.platSizes.length; s++) {
            if (cfg.platSizes[s] !== prevSize) sizes.push(cfg.platSizes[s]);
        }
        var w = isGoal ? cfg.goalPlatW
                       : sizes[Math.floor(rand(r) * sizes.length)];
        var glyph = isGoal ? cfg.finishGlyph : glyphForSize(cfg, w);

        var roomR = (cfg.baseW - cfg.genEdge) - (prev.x + prev.w);
        var roomL = prev.x - cfg.genEdge;
        // A bridge only counts when it can be long: if the roomier side cannot
        // fit one, the step becomes a normal hop rather than a stubby flat step.
        if (kind === "bridge"
                && Math.max(roomR, roomL) - w < cfg.genBridgeGapMin) {
            kind = "single";
        }
        var dh = kind === "bridge" ? 0
               : (kind === "single" ? cfg.climbUnit : 2 * cfg.climbUnit);
        var y = prev.y - dh;
        var minReq = kind === "bridge" ? cfg.genBridgeGapMin : cfg.genMinGap;
        var gapTarget = minReq + Math.floor(rand(r)
                * ((kind === "bridge" ? cfg.genBridgeGapMax : cfg.genClimbGapMax)
                   - minReq + 1));

        // current heading first, then bounce; a bridge tries the roomier side
        var dirs = (kind === "bridge" && roomL > roomR)
                 ? [-1, 1] : [heading, -heading];
        var placed = null;
        for (var d = 0; d < 2 && !placed; d++) {
            var dir = dirs[d];
            var room = (dir > 0 ? roomR : roomL) - w;
            if (room < minReq) continue;
            var gap = Math.min(gapTarget, room);
            var x = dir > 0 ? prev.x + prev.w + gap : prev.x - gap - w;
            if (sameLevelHit(cfg, list, x, w, y)) continue;
            placed = { x: x, w: w, dir: dir };
        }
        if (!placed) return null;
        list.push({
            x: Math.round(placed.x), y: Math.round(y), w: placed.w,
            glyph: glyph, edge: i === cfg.platCount - 1, idx: i, kind: kind,
            sizeClass: isGoal ? -1 : cfg.platSizes.indexOf(w)
        });
        heading = placed.dir;
        prevKind = kind;
        prevSize = placed.w;
    }
    return valid(cfg, list) ? list : null;
}

// Full-layout check on the whole list: step heights, gaps, and level sharing.
function valid(cfg, list) {
    if (list.length !== cfg.platCount) return false;
    for (var i = 1; i < list.length; i++) {
        var a = list[i - 1], b = list[i];
        var dh = a.y - b.y;
        if (dh !== 0 && dh !== cfg.climbUnit && dh !== 2 * cfg.climbUnit) return false;
        var gap = b.x > a.x ? b.x - (a.x + a.w) : a.x - (b.x + b.w);
        if (gap < cfg.genMinGap - 1) return false;
        // horizontal airtime: flat/full-arc hops are the long ones
        var budget = dh === 0 ? 150 : (dh === cfg.climbUnit ? 92 : 120);
        if (gap > budget) return false;
    }
    for (var m = 0; m < list.length; m++) {
        for (var n = m + 1; n < list.length; n++) {
            var p = list[m], q = list[n];
            if (Math.abs(p.y - q.y) < cfg.climbUnit * 0.5
                    && p.x < q.x + q.w + cfg.genMinGap - 1
                    && q.x < p.x + p.w + cfg.genMinGap - 1) {
                return false;
            }
        }
    }
    return true;
}

// Deterministic ladder, used only when the walk cannot be placed at all.
function fallback(cfg, seed) {
    var r = { s: (seed ^ 0x5f3759df) >>> 0 };
    var list = [];
    var px = cfg.baseW / 2 - 60;
    for (var i = 0; i < cfg.platCount; i++) {
        var isGoal = i === cfg.platCount - 1;
        var w = (i === 0) ? cfg.basePlatW
                : (isGoal ? cfg.goalPlatW
                          : cfg.platSizes[Math.floor(rand(r) * cfg.platSizes.length)]);
        px += (rand(r) * 2 - 1) * 55;
        if (px < 8) px = 8;
        if (px > cfg.baseW - w - 8) px = cfg.baseW - w - 8;
        var glyph = i === 0 ? cfg.glyphs[0]
                  : (isGoal ? cfg.finishGlyph : glyphForSize(cfg, w));
        list.push({
            x: Math.round(px), y: cfg.platBaseY - i * cfg.climbUnit, w: w,
            glyph: glyph, edge: (i === 0 || isGoal),
            idx: i, kind: "single",
            sizeClass: (i === 0 || isGoal) ? -1 : cfg.platSizes.indexOf(w)
        });
    }
    return list;
}

// Deterministic level: one seed gives one course. Up to 64 walk attempts,
// then the ladder.
function build(cfg, seed) {
    for (var attempt = 0; attempt < 64; attempt++) {
        var seedObj = { s: (seed + attempt * 104729) >>> 0 };
        var list = grow(cfg, seedObj);
        if (list) return list;
    }
    return fallback(cfg, seed);
}
