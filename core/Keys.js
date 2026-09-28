// The keyboard layout, as pure functions.
//
// The view (Panel.qml) owns the live key set (`keysDown`, a map of pressed Qt
// key codes) and the pad state; this module owns the layout and solo merging.
//
//   P1 : A/D + W or Space
//   P2 : Left/Right + Up or Enter (the main Return and the numpad Enter, which
//        Qt reports as two different keys)
//   solo (P2 not in the round): both sets drive P1. The arrows cannot join P2
//        on their own; `p2PadInput` is the only join trigger.
//   colour switch (Match or Fall only): E for P1, / for P2, folded into P1 in
//        solo like the arrows are. On a pad the reference game uses X per pad;
//        this plugin already spends B and X on P2's jump, so the shoulders take
//        that role: LB for P1, RB for P2.
//
// Pad inputs are per-player and additive over the keyboard.
.pragma library

// Deadzone for a stick axis: below it a stick is at rest, past it a full
// deflection.
var DEADZONE = 0.35;

function axis(pad, name) {
    var n = Number(pad ? pad[name] : 0);
    if (!isFinite(n)) return 0;
    return n < -1 ? -1 : (n > 1 ? 1 : n);
}

function p1Left(keys, pad, p2Joined) {
    return !!keys[Qt.Key_A] || (!p2Joined && !!keys[Qt.Key_Left])
        || !!pad.p1left || axis(pad, "p1x") < -DEADZONE;
}

function p1Right(keys, pad, p2Joined) {
    return !!keys[Qt.Key_D] || (!p2Joined && !!keys[Qt.Key_Right])
        || !!pad.p1right || axis(pad, "p1x") > DEADZONE;
}

function p1Jump(keys, pad, p2Joined) {
    return !!keys[Qt.Key_W] || !!keys[Qt.Key_Space]
        || (!p2Joined && (!!keys[Qt.Key_Up] || !!keys[Qt.Key_Return]
                          || !!keys[Qt.Key_Enter]))
        || !!pad.p1jump;
}

function p2Left(keys, pad) {
    return !!keys[Qt.Key_Left] || !!pad.p2left || axis(pad, "p2x") < -DEADZONE;
}

function p2Right(keys, pad) {
    return !!keys[Qt.Key_Right] || !!pad.p2right || axis(pad, "p2x") > DEADZONE;
}

function p2Jump(keys, pad) {
    return !!keys[Qt.Key_Up] || !!keys[Qt.Key_Return] || !!keys[Qt.Key_Enter]
        || !!pad.p2jump;
}

// The colour switch (Match or Fall), the same way for both players so the edge
// handling in the engine needs no per-player branch.
function p1Form(keys, pad, p2Joined) {
    return !!keys[Qt.Key_E] || (!p2Joined && !!keys[Qt.Key_Slash]) || !!pad.p1form;
}

function p2Form(keys, pad) {
    return !!keys[Qt.Key_Slash] || !!pad.p2form;
}

// What a *pad* is doing for P2, Panel's only join trigger. The keyboard's P2
// keys are absent on purpose, since in solo they belong to P1.
function p2PadInput(pad) {
    return !!pad.p2left || !!pad.p2right || !!pad.p2jump
        || axis(pad, "p2x") < -DEADZONE || axis(pad, "p2x") > DEADZONE;
}
