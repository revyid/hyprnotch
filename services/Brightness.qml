pragma Singleton

//  Screen brightness via the kernel sysfs interface + brightnessctl.
//
//  Volume has it easy: Pipewire announces every change. Brightness
//  announces nothing — a keybind press is a raw write to a kernel file.
//  But the file can be WATCHED: a FileView with `watchChanges` sees every
//  write with zero processes, so whoever changes brightness (keys, scroll,
//  another tool) still pops the HUD exactly like volume does.
//
//  Machines without a backlight class (desktop + DDC monitors) fall back
//  to a short `brightnessctl -m` poll — less instant, still pops the HUD.
//
//  Reading goes straight through FileView.text() / process output (no
//  reused cat processes), and writing goes through Quickshell.execDetached
//  (no Process reuse races when keys are held down).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: brightness

    property int level: 100          //  0..100
    property bool available: false   //  brightnessctl exists (with or without backlight)
    property bool hudOpen: false
    property bool initialized: false //  first measurement must not pop the HUD
    property string devicePath: ""   //  /sys/class/backlight/<dev>/brightness
    property int maxRaw: 0

    //  ── Startup probe: is brightnessctl present, and is there a sysfs
    //     device? One shot, then everything else is watching or polling.
    Process {
        command: ["sh", "-c",
            "command -v brightnessctl >/dev/null 2>&1 && echo ok; "
            + "d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1); "
            + "if [ -n \"$d\" ]; then cat \"$d/max_brightness\"; echo \"$d/brightness\"; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                    .filter(function (l) { return l.length > 0 })
                if (lines.length === 0 || lines[0] !== "ok")
                    return  //  no brightnessctl: no brightness support at all
                brightness.available = true
                if (lines.length >= 3 && lines[2].indexOf("/brightness") > 0) {
                    const max = parseInt(lines[1], 10)
                    if (isFinite(max) && max > 0) {
                        brightness.maxRaw = max
                        brightness.devicePath = lines[2]
                        sysfs.path = lines[2]
                    }
                }
                //  No backlight path → DDC machine: poller handles it.
            }
        }
    }

    //  The watcher. An external brightness change is a write here; reload
    //  then read the fresh value straight from the FileView.
    FileView {
        id: sysfs
        path: brightness.devicePath
        watchChanges: brightness.devicePath.length > 0
        onFileChanged: reload()
        onLoaded: brightness.readSysfs()
    }

    function readSysfs() {
        if (maxRaw <= 0)
            return
        const cur = parseInt(sysfs.text().trim(), 10)
        if (!isFinite(cur))
            return
        apply(Math.round(cur / maxRaw * 100))
    }

    function readFromMeter() {
        meter.command = ["sh", "-c", "brightnessctl -m 2>/dev/null | head -1"]
        meter.running = true
    }

    Process {
        id: meter
        stdout: StdioCollector {
            onStreamFinished: {
                //  brightnessctl -m: class,device,current,max,percent,...
                const p = text.trim().split(",")
                const cur = parseInt(p[2], 10), max = parseInt(p[3], 10)
                if (isFinite(cur) && isFinite(max) && max > 0)
                    apply(Math.round(cur / max * 100))
            }
        }
    }

    //  DDC fallback poll — only when there is no sysfs file to watch.
    Timer {
        interval: 2500
        repeat: true
        running: brightness.available && brightness.devicePath.length === 0
        onTriggered: brightness.readFromMeter()
    }

    function apply(pct) {
        if (!isFinite(pct))
            return
        pct = Math.max(0, Math.min(100, pct))
        const changed = initialized && pct !== level
        level = pct
        initialized = true
        if (changed)
            flashHud()
    }

    function setLevel(pct) {
        const p = Math.max(1, Math.min(100, Math.round(pct)))
        if (!available)
            return
        level = p
        initialized = true
        Quickshell.execDetached(["brightnessctl", "set", p + "%"])
        flashHud()
    }

    Timer {
        id: hudTimer
        interval: Config.get("hud.timeout", 1600)
        onTriggered: brightness.hudOpen = false
    }

    function flashHud() {
        if (!Config.get("hud.enabled", true))
            return
        hudOpen = true
        hudTimer.restart()
    }
}
