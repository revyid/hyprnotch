pragma Singleton

//  Power / session actions + night light (hyprsunset) + power profiles
//  (powerprofilesctl) + misc built-in command runners. Every action is
//  a plain shell command so users can mirror the behavior in scripts.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: power

    property bool nightActive: false

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

    function screenshot()  { run("sh -c \"command -v grimblast >/dev/null && grimblast save area || (command -v grim >/dev/null && grim -g \\\"$(slurp)\\\" $HOME/Pictures/shot.png)\"") }
    function record()      { run("sh -c 'command -v wf-recorder >/dev/null && pkill -INT wf-recorder 2>/dev/null || wf-recorder -f $HOME/Videos/rec.mp4 & disown'") }

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
        } else {
            run("sh -c 'command -v hyprsunset >/dev/null && nohup hyprsunset -t 3400 >/dev/null 2>&1 & disown'")
            nightActive = true
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

    Component.onCompleted: {
        probe.running = true
        probeProfile()
    }
}
