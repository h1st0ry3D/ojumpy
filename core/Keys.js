// The keyboard layout, as pure functions.
//
// The view (Panel.qml) owns the live key set (`keysDown`, a map of pressed Qt
// key codes) and the pad state; this module owns the *layout* — which keys mean
// what, and how solo play merges the two key sets. Keeping it here means a
// remap is one table and the behaviour can be checked without a window.
//
//   P1 : A/D + W or Space
//   P2 : Left/Right + Up or Enter (the main Return and the numpad Enter, which
//        Qt reports as two different keys)
//   solo (P2 not in the round): both sets drive P1, so a lone player can use
//        either hand layout. That is why the arrows must also NOT be able to
//        join P2 on their own — `p2PadInput` is the join trigger, and it only
//        looks at the pad.
//
// Pad inputs are per-player and additive on top of the keyboard: keyboard and
// pad can drive the same racer at the same time.
.pragma library

// Deadzone for a stick axis. Below it a stick is at rest; the game is digital,
// so anything past it counts as a full deflection.
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

// What a *pad* is doing for P2: Panel's join trigger. The keyboard's P2 keys
// are deliberately absent — in solo they belong to P1, so an arrow key would
// otherwise split the screen on the first press.
function p2PadInput(pad) {
    return !!pad.p2left || !!pad.p2right || !!pad.p2jump
        || axis(pad, "p2x") < -DEADZONE || axis(pad, "p2x") > DEADZONE;
}
