// Flattening for text that the *shell* renders (tooltipText, PanelToolTip):
// those widgets use AutoText, so markup in the string would be interpreted —
// rich text loads <img src="...">, i.e. a request from the shell process.
// Everything dynamic that goes into such a sink passes through plain() first.
.pragma library

var MAX_LEN = 96

function plain(value) {
    var s = String(value === undefined || value === null ? "" : value);
    return s.replace(/[<>&]/g, "")                                  // markup
            .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")           // C0/C1 controls
            .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "") // bidi controls
            .slice(0, MAX_LEN);
}
