import QtQuick
import Quickshell
import Quickshell.Io
import "../core/GameModes.js" as Modes

// Debug IPC surface: `omarchy-shell ojumpy.debug <fn> x` (see README).
//
// Read-only except for the round controls (start/join/leave/fullscreen); the
// engine is the single source of truth, so these handlers just forward.
// `panel` is the plugin root (scale factors, flags, formatting) and `dropdown`
// the game panel instance (card metrics for `dims`).
Item {
    id: debugIpc

    required property var game        // GameEngine
    required property var panel       // Panel root
    required property var dropdown    // GamePanel instance

    IpcHandler {
        target: "ojumpy.debug"

        function start(x: string): string {
            var s = parseInt(x);
            debugIpc.game.startRound(isFinite(s) && s > 0 ? s : undefined);
            debugIpc.panel.modesOpen = false;
            return "started " + debugIpc.game.roundSeed;
        }

        function join(x: string): string {
            debugIpc.game.joinP2();
            return debugIpc.game.p2Joined ? "joined" : "failed";
        }

        function leave(x: string): string {
            debugIpc.game.leaveP2();
            return debugIpc.game.p2Joined ? "failed" : "left";
        }

        function pause(x: string): string {
            debugIpc.game.pauseGame();
            return debugIpc.game.paused ? "paused" : "not running";
        }

        function resume(x: string): string {
            debugIpc.game.resumeGame();
            return debugIpc.game.paused ? "failed" : "running";
        }

        function mode(x: string): string {
            if (!Modes.isReady(x)) return "unknown or not ready: " + x;
            debugIpc.game.modeId = x;
            debugIpc.panel.modesOpen = false;
            return "mode " + x;
        }

        function state(x: string): string {
            var g = debugIpc.game;
            var p = debugIpc.panel;
            return JSON.stringify({active: g.roundActive, paused: g.paused, elapsed: g.elapsed,
                winner: g.winner, mode: g.modeId, seed: g.roundSeed,
                p2Joined: g.p2Joined, split: g.p2Joined,
                p1: [Math.round(g.p1x * p.scaleX), Math.round(g.p1y * p.scaleY)],
                p2: [Math.round(g.p2x * p.scaleX), Math.round(g.p2y * p.scaleY)],
                falls: [g.falls1, g.falls2],
                p1Plat: g.p1Plat, p1Jumps: g.p1Jumps, camY: Math.round(g.camY1),
                camY1: Math.round(g.camY1), camY2: Math.round(g.camY2),
                camX1: Math.round(g.camX1), camX2: Math.round(g.camX2),
                glide: [g.p1Gliding, g.p2Gliding], vy: [Math.round(g.p1vy), Math.round(g.p2vy)],
                rocks: debugIpc.game.hazardCount(),
                bold: [debugIpc.game.p1Bold, debugIpc.game.p2Bold],
                powerup: [debugIpc.game.powerupLive(0), debugIpc.game.powerupLive(1)],
                orb: [Math.round(g.orbX), Math.round(g.orbY), g.orbTaken, g.orbWinner],
                score: [g.p1Score, g.p2Score], target: g.scoreTarget,
                idle: [Math.round(g.p1Idle * 10) / 10, Math.round(g.p2Idle * 10) / 10],
                ghosts: [g.ghostCount(0), g.ghostCount(1)],
                pad: p.pad && p.pad.connected, green: p.themeGreen});
        }

        function modes(x: string): string {
            var out = [];
            var l = Modes.list();
            for (var i = 0; i < l.length; i++)
                out.push({ id: l[i].id, name: l[i].name, ready: l[i].ready,
                           current: l[i].id === debugIpc.game.modeId });
            return JSON.stringify(out);
        }

        function dims(x: string): string {
            var g = debugIpc.game;
            var p = debugIpc.panel;
            var d = debugIpc.dropdown;
            return JSON.stringify({fs: p.fsFullscreen,
                arenaW: Math.round(440 * p.scaleX), arenaH: Math.round(500 * p.scaleY),
                viewportW: g.viewportW, boardW: Math.round(p._boardUnits * p.scaleX), p2: g.p2Joined,
                shellScale: p.shellScale, seed: g.roundSeed,
                scaleX: p.scaleX, scaleY: p.scaleY, uiScale: p.uiScale,
                barLabel: p.barLabel, barW: Math.round(p.implicitWidth),
                availW: Math.round(d ? d.availableCardWidth : -1),
                availH: Math.round(d ? d.availableCardHeight : -1),
                contentW: Math.round(d ? d.contentWidth : -1),
                contentH: Math.round(d ? d.contentHeight : -1)});
        }

        function course(x: string): string {
            var out = [];
            var ps = debugIpc.game.platforms;
            for (var i = 0; i < ps.length; i++)
                out.push([ps[i].idx, ps[i].x, ps[i].y, ps[i].w, ps[i].kind, ps[i].glyph.substring(0, 2)]);
            return JSON.stringify({seed: debugIpc.game.roundSeed, n: ps.length, plats: out});
        }

        function fullscreen(x: string): string {
            debugIpc.panel.toggleFullscreen();
            return debugIpc.dims(x);
        }
    }
}
