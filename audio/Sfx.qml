import QtQuick
import Quickshell.Io

// Sound effects.
//
// The cues are synthesized by ojumpy-sfx.py and ship as WAVs in `sfx/` (committed,
// so a clone is complete). Each cue has a few pitch variants, played at random:
// a fixed pitch every 0.3 s becomes grating.
//
// The WAVs are read-only here — rendering them at startup would write into the
// folder the shell hot-reloads. Regenerate by hand with `python3 -B ojumpy-sfx.py`.
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

    // cues live in ./sfx, resolved relative to this file so the plugin works
    // wherever it was cloned
    readonly property url sfxUrl: Qt.resolvedUrl("sfx/")
    readonly property string dir: (function () {
        var d = decodeURIComponent(sfxUrl.toString().replace(/^file:\/\//, ""));
        return d.slice(-1) === "/" ? d : d + "/";
    })()
    readonly property int voiceCount: 5   // len(PITCH_SCALES) in ojumpy-sfx.py
    property string audioPlayer: ""       // probed once at startup
    property string lastCommand: ""       // last cue actually handed to a voice

    // pw-play (PipeWire), paplay (Pulse), aplay (ALSA): the first that exists
    // wins, so any of those stacks can play the cues. Absolute paths, and the
    // probe is argv-only `test -x` runs answered by exit codes — no shell string
    // and no output collector (neither has a byte cap the caller controls).
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

    // Playback voices, round-robin: a cue that is still sounding must not be cut
    // off by the next one (a 180 ms bump under 0.3 s footsteps is ordinary when
    // two players shove).
    Process { id: sfxV0 }
    Process { id: sfxV1 }
    Process { id: sfxV2 }
    Process { id: sfxV3 }
    readonly property var voices: [sfxV0, sfxV1, sfxV2, sfxV3]
    property int next: 0

    // One cue: random pitch variant, next voice. Silent while the panel is
    // closed — the sim keeps ticking in the background, so a held pad button
    // must not keep clicking footsteps out of the bar.
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
        // a hazard death (Asterisk Attack): the same short thud as a body bump
        function onCrushed(playerIdx) { sfx.play("bump") }
        // catching the platform-50 power-up / spending it on a rock
        function onPowered(playerIdx) { sfx.play("land") }
        function onShielded(playerIdx) { sfx.play("bump") }
        // touched the summit orb: the collectible arpeggio
        function onOrbCollected(playerIdx) { sfx.play("orb") }
        // Glyph Hunt: your colour is a bright bing, the other one a sad möp
        // a wrong-colour glyph is a death: it plays through onCrushed below (the
        // same thud as shoving the other player), so only the good catch rings
        function onCollected(playerIdx, correct) { if (correct) sfx.play("bing") }
        // leaving the ground, ground jump and air jump alike
        function onJumped(playerIdx) { sfx.play("jump") }
    }
}
