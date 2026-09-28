// The two players' letters, as pure data.
//
// Each player is a letter with two dots over it, and the letter differs per player
// so the two are told apart by shape as well as by colour: player 1 is the O face,
// player 2 the U face. Every state of a face is that same letter with its dots
// kept (the face), dropped (the closed-eye blink) or topped (the glider's hat), so
// a player's identity holds in every mode and at every moment of a round.
//
// The dead marker is shared and lives in the view: Ø is a crossed letter, not a
// face, and there is no crossed U to match it with.
//
// All eight characters sit on the same 0.6 em advance, and Ü/Û paint exactly as
// high and as low as Ö/Ô, so the art grid and the engine's painted-height constant
// hold for both faces without a per-player value. (ü and u are a hundredth of an em
// shorter than ö and o, which only ever shows as the asleep face, never as the
// painted body a contact test uses.)
.pragma library

var FACES = [
    { letter: "Ö", sleep: "ö", blink: "o", glide: "Ô" },   // player 1
    { letter: "Ü", sleep: "ü", blink: "u", glide: "Û" }    // player 2
];

// A player's face by player index. An index that is not 0 or 1 draws player 1's,
// so a lookup can never come back empty.
function of(idx) {
    return FACES[idx === 1 ? 1 : 0];
}

// Every character a face can be drawn as, both players': what the view measures
// once, so either player's ink box is measured whichever is on screen.
function glyphs() {
    var out = [];
    for (var i = 0; i < FACES.length; i++) {
        var f = FACES[i];
        out.push(f.letter, f.sleep, f.blink, f.glide);
    }
    return out;
}
