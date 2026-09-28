import QtQuick
import Quickshell.Io

// Sound effects.
//
// The cues are synthesized by ojumpy-sfx.py; the rendered WAVs are committed in
// `sfx/`. Regenerate by hand with `python3 -B ojumpy-sfx.py`, never at startup:
// that would write into the folder the shell hot-reloads.
//
// `enabled` (the panel being open) belongs to the caller; playback belongs here.
//
// Root is a zero-sized Item because QtObject has no default property for the
// Process children.
Item {
    id: sfx
    width: 0
    height: 0

    required property var game        // the engine: supplies stepped/landed/bumped
    required property bool enabled    // false while the panel is closed

    readonly property url sfxUrl: Qt.resolvedUrl("sfx/")
    readonly property string dir: (function () {
        var d = decodeURIComponent(sfxUrl.toString().replace(/^file:\/\//, ""));
        return d.slice(-1) === "/" ? d : d + "/";
    })()
    readonly property int voiceCount: 5   // len(PITCH_SCALES) in ojumpy-sfx.py
    property string audioPlayer: ""       // probed once at startup
    property string lastCommand: ""       // last cue actually handed to a voice

    // pw-play (PipeWire), paplay (Pulse), aplay (ALSA): the first that exists
    // wins, and the probe is an argv-only `/usr/bin/test -x` answered by its
    // exit code, never a shell string.
    readonly property var audioCandidates: ["/usr/bin/pw-play", "/usr/bin/paplay", "/usr/bin/aplay"]
    property int audioProbeIdx: 0
    Process {
        id: audioProbe
        command: ["/usr/bin/test", "-x", sfx.audioCandidates[sfx.audioProbeIdx]]
        running: true
        onExited: function (code) {
            if (code === 0) { sfx.audioPlayer = sfx.audioCandidates[sfx.audioProbeIdx]; return; }
            if (sfx.audioProbeIdx < sfx.audioCandidates.length - 1) {
                sfx.audioProbeIdx = sfx.audioProbeIdx + 1;
                running = true;
            }
        }
    }

    // Four playback voices, round-robin, so a cue that is still sounding is not
    // cut off by the next one.
    Process { id: sfxV0 }
    Process { id: sfxV1 }
    Process { id: sfxV2 }
    Process { id: sfxV3 }
    readonly property var voices: [sfxV0, sfxV1, sfxV2, sfxV3]
    property int next: 0

    // One cue: random pitch variant, next voice. Skipped while the panel is
    // closed, because the sim keeps ticking in the background.
    function play(cue) {
        if (!sfx.audioPlayer || !sfx.enabled) return;
        var v = sfx.voices[sfx.next];
        sfx.next = (sfx.next + 1) % sfx.voices.length;
        var file = sfx.dir + cue + "-" + Math.floor(Math.random() * sfx.voiceCount) + ".wav";
        sfx.lastCommand = file;
        v.command = [sfx.audioPlayer, file];
        v.running = false;      // recycle the voice
        v.running = true;
    }

    Connections {
        target: sfx.game
        function onStepped(playerIdx) { sfx.play("step") }
        function onLanded(playerIdx) { sfx.play("land") }
        function onBumped() { sfx.play("bump") }
        // a hazard kill: a rock in Asterisk Attack, the other player's colour in
        // Glyph Hunt. Both die through the same path (_crush), one cue.
        function onCrushed(playerIdx) { sfx.play("hit") }
        // fell off the bottom of the tower, in any mode: the same hit
        function onFell(playerIdx) { sfx.play("hit") }
        // catching the platform-50 power-up / spending it on a rock
        function onPowered(playerIdx) { sfx.play("land") }
        function onShielded(playerIdx) { sfx.play("bump") }
        // touched the summit orb: the collectible arpeggio
        function onOrbCollected(playerIdx) { sfx.play("orb") }
        // Glyph Hunt: a wrong-colour glyph plays through onCrushed above, so
        // only a correct catch rings here.
        function onCollected(playerIdx, correct) { if (correct) sfx.play("bing") }
        // leaving the ground, ground jump and air jump alike
        function onJumped(playerIdx) { sfx.play("jump") }
    }
}
