pragma Singleton

//  Audio visualizer (r25) — the "cava pas musicnya idup" request.
//
//  When a player is actually PLAYING, the island shows a little
//  spectrum. Two engines, picked honestly:
//
//    · real     — the `cava` binary, run with our own generated config
//                 (noncurses output, one line of bar values per frame,
//                 ';' separated). Parsed line-by-line with SplitParser,
//                 so no polling and no temp files.
//    · fallback — a smooth synthetic motion (three detuned sine banks
//                 + jitter, bass-weighted) driven by a 15 fps timer.
//                 No dependencies, and it only ever runs while a
//                 player reports isPlaying.
//
//  Consumers read `bars` (count values, 0..1) through island/CavaBars.
//  A watchdog demotes a silent real engine to the fallback instead of
//  freezing the bars (cava can start and print nothing when no sink
//  monitor is available). Feature switch: island.cava.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: cava

    readonly property bool enabled: Config.get("island.cava", true)
    readonly property bool active: enabled && Media.playing

    readonly property int count: 14

    property var bars: []                  // count values, 0..1
    property bool toolAvailable: false     // cava binary probed OK
    property bool usingTool: false         // real engine currently feeds bars
    property bool toolFailed: false        // cava died/went silent this session
    property bool gotData: false           // reset on engine start (watchdog)
    property real autoMax: 55              // running amplitude ceiling (auto-sens)

    function setBars(list) {
        bars = list
    }

    Component.onCompleted: {
        const init = []
        for (let i = 0; i < count; ++i)
            init.push(0)
        bars = init
        probe.running = true
    }

    //  ── Engine selection ─────────────────────────────────────────
    //  Re-run whenever the feature flag flips or Media starts/stops
    //  playing: the real engine only stays alive while it has
    //  something to visualize. A NEW play session clears toolFailed —
    //  one honest retry per session, never a restart loop.
    onEnabledChanged: applyEngine()
    onActiveChanged: {
        if (active)
            toolFailed = false
        applyEngine()
    }

    function applyEngine() {
        if (active && toolAvailable && !usingTool && !toolFailed)
            startReal()
        else if ((!active || !toolAvailable) && usingTool)
            stopReal()
        fallbackTimer.running = active && !usingTool
        if (!active) {
            const flat = []
            for (let i = 0; i < count; ++i)
                flat.push(0)
            bars = flat
        }
    }

    function startReal() {
        gotData = false
        usingTool = true
        cavaProc.running = true
        watchdog.restart()
    }

    function stopReal() {
        watchdog.stop()
        cavaProc.running = false
        usingTool = false
        applyEngine()
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                cava.toolAvailable = (text.trim() === "yes")
                cava.applyEngine()
            }
        }
    }

    //  cava in noncurses mode: one frame per line, values joined by the
    //  bar delimiter (59 = ';'). Config is generated at runtime into
    //  XDG_RUNTIME_DIR so we never touch the user's ~/.config/cava.
    readonly property string cavaScript: {
        const conf = "${XDG_RUNTIME_DIR:-/tmp}/hyprnotch-cava.conf"
        //  The assignment must stay UNQUOTED or the shell would treat
        //  ${XDG_RUNTIME_DIR:-/tmp} as literal text instead of a
        //  parameter expansion (the path never contains spaces).
        return "conf=" + conf + "; "
            + "printf '[general]\\nbars = " + count + "\\nframerate = 30\\nautosens = 1\\n"
            + "[output]\\nmethod = noncurses\\nbar_delimiter = 59\\n' > \"$conf\"; "
            + "exec cava -p \"$conf\""
    }

    Process {
        id: cavaProc
        command: ["sh", "-c", cava.cavaScript]
        stdout: SplitParser {
            onRead: (line) => cava.eat(line)
        }
        onExited: {
            //  cava died (no sink monitor, killed, whatever) — mark the
            //  engine failed for this session and fall back, instead of
            //  restart-looping on a binary that cannot attach.
            if (cava.usingTool) {
                cava.toolFailed = true
                cava.usingTool = false
                cava.watchdog.stop()
                cava.applyEngine()
            }
        }
    }

    //  If the real engine ran 2.5 s without emitting a single frame,
    //  stop trusting it and let the fallback take the wheel.
    Timer {
        id: watchdog
        interval: 2500
        onTriggered: {
            if (cava.usingTool && !cava.gotData) {
                cava.toolFailed = true
                cava.usingTool = false
                cava.cavaProc.running = false
                cava.applyEngine()
            }
        }
    }

    function eat(line) {
        const t = String(line).replace(/\u001b\[[0-9;]*[A-Za-z]/g, "").trim()
        if (t.length === 0)
            return
        const parts = t.split(";")
        const out = []
        let peak = 0
        for (let i = 0; i < count; ++i) {
            const v = parseFloat(parts[Math.min(i, parts.length - 1)])
            const n = isFinite(v) && v > 0 ? v : 0
            if (n > peak)
                peak = n
            out.push(n)
        }
        //  Auto-sens like cava itself: grow the ceiling instantly on a
        //  louder peak, decay it slowly so quiet passages stay alive.
        if (peak > autoMax)
            autoMax = peak
        autoMax = Math.max(40, autoMax - 0.25)
        for (let j = 0; j < out.length; ++j)
            out[j] = Math.max(0.02, Math.min(1, out[j] / autoMax))
        gotData = true
        bars = out
    }

    //  ── Fallback engine: 15 fps synthetic motion ─────────────────
    property real t: 0

    Timer {
        id: fallbackTimer
        interval: 66
        running: false
        onTriggered: cava.synth()
    }

    function synth() {
        t += 1
        const out = []
        for (let i = 0; i < count; ++i) {
            const f = i / (count - 1)              // 0 = bass end
            let v = 0.34
                + 0.22 * Math.sin(t * 0.21 + i * 1.7)
                + 0.16 * Math.sin(t * 0.47 + i * 0.9 + 1.3)
                + 0.11 * Math.sin(t * 0.11 + i * 3.1)
                + Math.random() * 0.16
            v *= 1.3 - f * 0.5                     // bass kicks harder
            out.push(Math.max(0.05, Math.min(1, v)))
        }
        bars = out
    }
}
