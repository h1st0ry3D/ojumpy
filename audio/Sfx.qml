import QtQuick
import Quickshell.Io

// Sound effects.
//
// The cues are synthesized by ojumpy-sfx.py; the rendered WAVs are committed in
// `sfx/`. Regenerate by hand with `python3 -B ojumpy-sfx.py`, never at startup:
// that would write into the folder the shell hot-reloads.
//
// Playback is in memory: SfxVoice.qml holds one SoundEffect per committed WAV and
// a cue is a play() call, which is the only path with no process spawn in it. A
// `pw-play` invocation costs about 100 ms of setup before the first sample, and
// on a death that is most of the delay. QtMultimedia is loaded through
// Qt.createComponent, so a Qt without it (or an in-memory pool that never
// becomes ready) falls back to handing a file to a player process, which is what
// the rest of this file is for.
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
    // the sfx directory as a plain path, no trailing separator
    readonly property string dir: (function () {
        var d = decodeURIComponent(sfxUrl.toString().replace(/^file:\/\//, ""));
        return d.slice(-1) === "/" ? d.slice(0, -1) : d;
    })()
    readonly property int voiceCount: 5   // len(PITCH_SCALES) in ojumpy-sfx.py
    // The cue names, and nothing else, must match the tables in ojumpy-sfx.py
    // (CUES, ARPEGGIOS, IMPACTS). A name missing here is silent in both paths.
    readonly property var cues: ["step", "land", "bump", "hit", "orb", "bing", "jump"]
    property string audioPlayer: ""       // probed once at startup
    // last cue actually played, whichever path served it, and which path that was
    property string lastCommand: ""
    property string lastPath: "none"

    // ---- in-memory pool (the fast path) ----
    // Loaded once, after this component. Null until then and forever on a Qt
    // without QtMultimedia, which is what keeps the process path reachable.
    property var voices: null
    property string voicesError: ""
    Component.onCompleted: sfx.loadVoices()
    function loadVoices() {
        var c = Qt.createComponent(Qt.resolvedUrl("SfxVoice.qml"));
        if (c.status === Component.Error) {
            sfx.voicesError = c.errorString();
            return;
        }
        sfx.voices = c.createObject(sfx, { "cues": sfx.cues, "voiceCount": sfx.voiceCount,
                                           "sfxUrl": sfx.sfxUrl });
    }

    // One cue: random pitch variant, next voice. Skipped while the panel is
    // closed, because the sim keeps ticking in the background.
    // ---- fallback: a player process per cue ----
    // Only reached when the in-memory pool is absent or not ready yet. It costs a
    // process spawn and a fresh PipeWire connection per cue, roughly 100 ms
    // before the first sample, which is why it is not the default.
    //
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
    readonly property var procs: [sfxV0, sfxV1, sfxV2, sfxV3]
    property int next: 0

    function fileFor(cue, variant) {
        return sfx.dir + "/" + cue + "-" + variant + ".wav";
    }

    // One cue: in memory when the pool is ready, otherwise a random pitch variant
    // on the next process voice. Skipped while the panel is closed, because the
    // sim keeps ticking in the background.
    function play(cue) {
        if (!sfx.enabled || sfx.cues.indexOf(cue) < 0) return;
        if (sfx.voices && sfx.voices.ready) {
            var inMemory = sfx.voices.play(cue);
            if (inMemory) {
                sfx.lastCommand = inMemory;
                sfx.lastPath = "in-memory";
                return;
            }
        }
        if (!sfx.audioPlayer) return;
        var v = sfx.procs[sfx.next];
        sfx.next = (sfx.next + 1) % sfx.procs.length;
        var file = sfx.fileFor(cue, Math.floor(Math.random() * sfx.voiceCount));
        sfx.lastCommand = file;
        sfx.lastPath = "process";
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
