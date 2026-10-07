pragma Singleton

//  Wallpaper service — awww or swww under the hood.
//
//  awww is the maintained fork that ships on Omarchy-style systems; the
//  two are CLI-identical, so the tool is auto-detected once at startup
//  (awww preferred, swww as fallback). Scans the usual wallpaper
//  folders (plus a user-configured one), lists previews for the picker
//  grid, and applies images with live transitions. The daemon is
//  started on demand if it is not running.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: wallpaper

    readonly property string home: Quickshell.env("HOME") || ""

    property var files: []               //  absolute paths
    property string current: Config.get("wallpaper.current", "")
    property bool scanning: false
    property bool available: false       //  wallpaper tool (awww/swww) exists
    property bool daemonRunning: false
    property string tool: "swww"         //  detected CLI: awww or swww

    readonly property string extraDir: Config.get("wallpaper.dir", "")
    readonly property string transition: Config.get("wallpaper.transition", "grow")
    readonly property real duration: Config.get("wallpaper.duration", 0.8)

    readonly property var defaultDirs: [
        home + "/Pictures/Wallpapers",
        home + "/Pictures/wallpapers",
        home + "/Pictures/Wallpaper",
        home + "/Pictures",
        home + "/Downloads",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    function dirs() {
        const out = []
        for (let i = 0; i < defaultDirs.length; ++i)
            if (out.indexOf(defaultDirs[i]) < 0)
                out.push(defaultDirs[i])
        if (extraDir.length > 0 && extraDir.indexOf(home) === 0 && out.indexOf(extraDir) < 0)
            out.unshift(extraDir)
        return out
    }

    Component.onCompleted: {
        checkProbe.running = true
        scanTimer.restart()
    }

    //  Rescan when the extra dir changes.
    onExtraDirChanged: scanTimer.restart()

    Timer {
        id: scanTimer
        interval: 600
        onTriggered: wallpaper.scan()
    }

    Process {
        id: checkProbe
        command: ["sh", "-c",
            "if command -v awww >/dev/null 2>&1; then echo tool awww; " +
            "elif command -v swww >/dev/null 2>&1; then echo tool swww; fi; " +
            "(pgrep -x awww-daemon >/dev/null 2>&1 || pgrep -x awww >/dev/null 2>&1 || " +
            " pgrep -x swww-daemon >/dev/null 2>&1 || pgrep -x swww >/dev/null 2>&1) && echo daemon || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    const parts = lines[i].trim().split(/\s+/)
                    if (parts[0] === "tool" && parts[1])
                        wallpaper.tool = parts[1]
                }
                wallpaper.available = (wallpaper.tool.length > 0 &&
                                       lines.findIndex(l => l.startsWith("tool")) >= 0)
                wallpaper.daemonRunning = (lines.indexOf("daemon") >= 0)
            }
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                const list = []
                if (out.length > 0) {
                    const rows = out.split("\n")
                    for (let i = 0; i < rows.length; ++i) {
                        const p = rows[i].trim()
                        if (p.length > 0 && list.indexOf(p) < 0)
                            list.push(p)
                    }
                }
                list.sort()
                wallpaper.files = list
                wallpaper.scanning = false
            }
        }
    }

    function scan() {
        scanning = true
        const ds = dirs()
        let cmd = ""
        for (let i = 0; i < ds.length; ++i) {
            cmd += (i > 0 ? "; " : "")
            cmd += "find '" + ds[i].replace(/'/g, "'\\''") + "' -maxdepth 3 -type f " +
                   "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
                   "-o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \\) 2>/dev/null"
        }
        cmd += " | head -300"
        scanProc.command = ["sh", "-c", cmd]
        scanProc.running = true
    }

    function apply(path) {
        if (!available || !path || path.length === 0)
            return
        const esc = String(path).replace(/'/g, "'\\''")
        let cmd = ""
        if (!daemonRunning)
            cmd += "(" + tool + "-daemon >/dev/null 2>&1 & disown; sleep 0.4); "
        cmd += tool + " img '" + esc + "'" +
               " --transition-type " + transition +
               " --transition-duration " + duration +
               " --transition-fps 60 2>/dev/null"
        Quickshell.execDetached(["sh", "-c", cmd])
        current = path
        Config.set("wallpaper.current", path)
        daemonRunning = true
        Notifs.toast("Wallpaper", "Applied: " + path.split("/").pop())
    }

    function openFolder() {
        const dir = (extraDir.length > 0 ? extraDir : home + "/Pictures")
        Power.run("sh -c 'for f in nautilus thunar dolphin nemo pcmanfm xdg-open; do command -v $f >/dev/null && exec $f \"" +
                  dir.replace(/"/g, "") + "\"; done'")
    }

    function fileName(path) {
        const s = String(path || "")
        return s.substring(s.lastIndexOf("/") + 1)
    }
}
