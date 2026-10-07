pragma Singleton

//  Power / session actions + night light (hyprsunset) + power profiles
//  (powerprofilesctl) + capture (screenshot / screen recording) + misc
//  built-in command runners. Every action is a plain shell command so
//  users can mirror the behavior in scripts.
//
//  r24 capture rework ("record kenapa ga works ya"): the old fire-and-
//  forget one-liners failed SILENTLY when wf-recorder/grimblast were
//  missing and gave zero feedback when they worked. Now:
//    · every tool is probed once at startup (wf-recorder, grimblast,
//      grim, slurp, hyprsunset) — missing tools are REPORTED,
//    · record() has real state: probe → start (timestamped file in
//      ~/Videos) or SIGINT-stop the running recorder, with a toast,
//    · screenshot() walks grimblast → grim+slurp → grim full-screen
//      and toasts where the shot was saved,
//    · the quick-actions tile can bind its active color to
//      Power.recording / Power.nightActive.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: power

    property bool nightActive: false

    //  ── capture state ─────────────────────────────────────────────
    property bool recording: false
    property string recordingFile: ""
    readonly property bool canRecord: bins["wf-recorder"] === true
    readonly property bool canScreenshot: bins["grimblast"] === true
        || (bins["grim"] === true && bins["slurp"] === true)
        || bins["grim"] === true

    //  ── tool availability (filled by the probe below) ─────────────
    property var bins: ({})

    function probeBin(name) {
        return bins[name] === true
    }

    //  ── power profiles (performance / balanced / power-saver) ─────
    //  "none" = powerprofilesctl missing (desktop without tuned/power-
    //  profiles-daemon) — the profile row simply hides.
    property string profile: "none"
    readonly property bool profileAvailable: profile !== "none"

    function setProfile(p) {
        if (p === profile || !profileAvailable)
            return
        Quickshell.execDetached(["sh", "-c", "powerprofilesctl set " + p + " 2>/dev/null"])
        profileProbeTimer.restart()
    }

    Timer {
        id: profileProbeTimer
        interval: 400
        onTriggered: power.probeProfile()
    }

    function probeProfile() {
        profileProbe.command = ["sh", "-c",
            "command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get 2>/dev/null || echo none"]
        profileProbe.running = true
    }

    Process {
        id: profileProbe
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.length > 0)
                    power.profile = t
            }
        }
    }

    //  ── session actions ───────────────────────────────────────────
    function lock()        { run("loginctl lock-session 2>/dev/null || hyprlock 2>/dev/null || swaylock 2>/dev/null") }
    function logout()      { run("hyprctl dispatch exit") }
    function suspend()     { run("systemctl suspend") }
    function reboot()      { run("systemctl reboot") }
    function shutdown()    { run("systemctl poweroff") }

    //  ── screenshot ────────────────────────────────────────────────
    //  grimblast (annotates + copies) → grim with a slurped region →
    //  grim full-screen last resort. Always tells the user what
    //  happened — a capture tool that fails in silence is broken.
    function screenshot() {
        if (!canScreenshot) {
            Notifs.toast("HyprNotch", "Screenshot unavailable",
                "install grim + slurp (or grimblast) — pacman -S grim slurp")
            return
        }
        shotProc.command = ["sh", "-c",
            "mkdir -p \"$HOME/Pictures\"; F=\"$HOME/Pictures/shot-$(date +%Y%m%d-%H%M%S).png\"; " +
            "if command -v grimblast >/dev/null 2>&1; then " +
            "    grimblast save area \"$F\" >/dev/null 2>&1 && echo \"OK|$F\" || echo \"FAIL|grimblast\"; " +
            "elif command -v slurp >/dev/null 2>&1; then " +
            "    R=\"$(slurp 2>/dev/null)\" && grim -g \"$R\" \"$F\" >/dev/null 2>&1 && echo \"OK|$F\" || echo \"FAIL|slurp\"; " +
            "else " +
            "    grim \"$F\" >/dev/null 2>&1 && echo \"OK|$F\" || echo \"FAIL|grim\"; fi"]
        shotProc.running = true
    }

    Process {
        id: shotProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.indexOf("OK|") === 0) {
                    const f = t.substring(3)
                    Notifs.toast("HyprNotch", "Screenshot saved",
                        f.replace(Quickshell.env("HOME"), "~"))
                } else {
                    Notifs.toast("HyprNotch", "Screenshot failed",
                        t.length > 0 ? t.replace("FAIL|", "tool: ") : "unknown error")
                }
            }
        }
    }

    //  ── screen recording ──────────────────────────────────────────
    //  wf-recorder only: it is THE Hyprland recorder (wlroots screen
    //  copy). Stop = SIGINT so it finalizes the container cleanly.
    function record() {
        if (!canRecord) {
            Notifs.toast("HyprNotch", "Recorder unavailable",
                "install wf-recorder — pacman -S wf-recorder")
            return
        }
        if (recording) {
            run("pkill -INT -x wf-recorder 2>/dev/null")
            Notifs.toast("HyprNotch", "Recording stopped",
                recordingFile.length > 0 ? recordingFile.replace(Quickshell.env("HOME"), "~") : "saved to ~/Videos")
            recording = false
            recordingFile = ""
            return
        }
        recProc.command = ["sh", "-c",
            "mkdir -p \"$HOME/Videos\"; F=\"$HOME/Videos/rec-$(date +%Y%m%d-%H%M%S).mp4\"; " +
            "nohup wf-recorder -f \"$F\" >/dev/null 2>&1 & sleep 0.6; " +
            "if pgrep -x wf-recorder >/dev/null 2>&1; then echo \"OK|$F\"; else echo \"FAIL|wf-recorder exited\"; fi"]
        recProc.running = true
    }

    Process {
        id: recProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.indexOf("OK|") === 0) {
                    power.recordingFile = t.substring(3)
                    power.recording = true
                    Notifs.toast("HyprNotch", "Recording started",
                        "Shift+Print or the quick action stops it")
                } else {
                    Notifs.toast("HyprNotch", "Recording failed",
                        t.length > 0 ? t.replace("FAIL|", "") : "wf-recorder did not start")
                }
            }
        }
    }

    //  Reflect reality at startup (a recorder started outside the
    //  notch should still make the tile glow) and after each toggle.
    //  While a recording is live, keep re-probing every few seconds so
    //  a recorder that dies on its own flips the tile back honestly.
    function probeRecording() {
        recStateProbe.running = true
    }

    Timer {
        id: recordingWatch
        running: power.recording
        repeat: true
        interval: 4000
        onTriggered: power.probeRecording()
    }

    Process {
        id: recStateProbe
        command: ["sh", "-c", "pgrep -x wf-recorder >/dev/null 2>&1 && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                const on = text.trim() === "on"
                if (on && !power.recording)
                    power.recordingFile = ""
                power.recording = on
            }
        }
    }

    function openTerminal(){ run("sh -c 'for t in alacritty kitty foot wezterm; do command -v $t >/dev/null && exec $t; done'") }
    function openFiles()   { run("sh -c 'for f in nautilus thunar dolphin nemo pcmanfm; do command -v $f >/dev/null && exec $f; done'") }

    function openSettings(page) {
        if (page !== undefined)
            UiState.settingsPage = page
        UiState.settingsOpen = true
    }

    function toggleNight() {
        if (nightActive) {
            run("pkill -f hyprsunset 2>/dev/null")
            nightActive = false
            Notifs.toast("HyprNotch", "Night light off", "")
        } else {
            if (!probeBin("hyprsunset")) {
                Notifs.toast("HyprNotch", "Night light unavailable",
                    "install hyprsunset — pacman -S hyprsunset")
                return
            }
            run("sh -c 'command -v hyprsunset >/dev/null && nohup hyprsunset -t 3400 >/dev/null 2>&1 & disown'")
            nightActive = true
            Notifs.toast("HyprNotch", "Night light on", "3400K")
        }
    }

    //  Night light survives logout only if hyprsunset is actually running;
    //  probe once at start so the toggle reflects reality.
    Process {
        id: probe
        command: ["sh", "-c", "pidof hyprsunset >/dev/null && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: power.nightActive = (text.trim() === "on")
        }
    }

    function run(cmd) {
        //  Fire-and-forget. execDetached survives command spam (no single
        //  Process object to fight over) and outlives rapid toggles.
        Quickshell.execDetached(["sh", "-c", cmd])
    }

    //  One probe for every optional binary the shell can drive. The
    //  result map drives both the capture actions above and the
    //  honest empty-states in the notch cards.
    Process {
        id: binProbe
        command: ["sh", "-c",
            "for b in wf-recorder grimblast grim slurp hyprsunset cliphist wl-copy wl-paste podman wtype; do " +
            "command -v \"$b\" >/dev/null 2>&1 && echo \"$b=yes\" || echo \"$b=no\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                const lines = text.trim().split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    const p = lines[i].split("=")
                    if (p.length === 2)
                        map[p[0]] = (p[1] === "yes")
                }
                power.bins = map
            }
        }
    }

    Component.onCompleted: {
        probe.running = true
        probeProfile()
        binProbe.running = true
        probeRecording()
    }
}
