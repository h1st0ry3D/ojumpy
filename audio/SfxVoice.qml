import QtQuick
import QtMultimedia

// In-memory cue playback.
//
// The WAVs are committed next to this file, so a cue does not need a player
// process: one SoundEffect per committed file, each with a fixed source, and a
// cue is a play() call. A `pw-play` invocation costs about 100 ms of spawn and
// PipeWire setup before the first sample, which is most of the delay on a death
// cue; this path spends none of it. 35 files, 700 KB on disk, loaded once.
//
// A cue that is still sounding is never cut off by the next one: every file has
// its own effect, and a cue's five pitch variants are five separate files, so
// repeated footsteps or two players scoring at once overlap freely.
//
// Sfx.qml loads this through Qt.createComponent, so a Qt without QtMultimedia
// leaves the caller on its process-based player instead of breaking the plugin.
// `ready` is the switch: it only turns true once every effect has decoded its
// file, so a cue is never handed to an effect with nothing loaded.
//
// Root is a zero-sized Item because QtObject has no default property for the
// Repeater.
Item {
    id: pool
    width: 0
    height: 0

    // the cue names, the variant count and the sfx URL come from Sfx.qml, which
    // is the single place that knows them
    required property var cues
    required property int voiceCount
    required property url sfxUrl

    // every committed file, in cue-major order: cue 0's variants first. The index
    // of a cue's variant v is therefore cueIndex * voiceCount + v.
    readonly property var files: {
        var out = [];
        for (var i = 0; i < pool.cues.length; i++) {
            for (var v = 0; v < pool.voiceCount; v++)
                out.push(pool.cues[i] + "-" + v + ".wav");
        }
        return out;
    }

    // Decoded effects so far. status is the only readiness signal SoundEffect
    // gives; it is also Ready for a file that failed to decode, which is why the
    // caller waits for every file rather than for the first one.
    property int readyCount: 0
    readonly property bool ready: pool.files.length > 0
                                   && pool.readyCount >= pool.files.length

    // the last file handed to an effect, and how many cues this pool has played
    property string lastFile: ""
    property int plays: 0
    // the next variant, rotating so a repeated cue does not always sound the same
    property int next: 0

    // Plays one cue and returns the file:// URL it started, or "" when the cue
    // is unknown or the pool is not ready.
    function play(cue) {
        var ci = pool.cues.indexOf(cue);
        if (ci < 0 || !pool.ready) return "";
        var variant = pool.next % pool.voiceCount;
        pool.next++;
        var cell = effects.itemAt(ci * pool.voiceCount + variant);
        if (!cell) return "";
        pool.lastFile = pool.files[ci * pool.voiceCount + variant];
        pool.plays++;
        cell.effect.play();
        return pool.sfxUrl + pool.lastFile;
    }

    Repeater {
        id: effects
        model: pool.files
        // The delegate is a zero-sized Item holding the effect, because
        // Repeater.itemAt() only returns its delegate for an Item type: with a
        // bare SoundEffect delegate the pool counts 35 but itemAt() answers null.
        delegate: Item {
            id: cell
            required property int index
            required property string modelData
            property alias effect: fx      // play() is reached through the cell
            width: 0
            height: 0
            SoundEffect {
                id: fx
                // the default is 1, which would play every cue twice
                loops: 0
                source: pool.sfxUrl + cell.modelData
                onStatusChanged: if (status === 2) pool.readyCount = pool.readyCount + 1
            }
        }
    }
}
