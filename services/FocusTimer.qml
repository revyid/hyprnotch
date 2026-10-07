pragma Singleton

//  Focus timer (r28) — a pomodoro-grade countdown that lives in the
//  notch. The service is pure state + a one-second tick; the pill shows
//  a live chip while a session runs, the Control Center hosts the
//  controls (preset chips 5/15/25/50, start/pause, reset), and finishing
//  a session raises a notification through the same daemon the banners
//  use.
//
//  Deliberately dependency-light on purpose: no scripts, no processes —
//  a Timer and arithmetic. The only external type touched is Notifs
//  (toast on completion), which keeps the service honest about when a
//  session actually ends even if every view is closed.

import QtQuick
import Quickshell

Singleton {
    id: focusTimer

    //  ── state ─────────────────────────────────────────────────────
    property bool running: false
    property int totalSeconds: 25 * 60       //  preset length of THIS session
    property int remaining: 25 * 60
    property int completions: 0              //  sessions finished since launch

    readonly property bool active: running || (remaining > 0 && remaining < totalSeconds)
    readonly property real progress: totalSeconds > 0
        ? Math.max(0, Math.min(1, 1 - remaining / totalSeconds)) : 0

    //  "MM:SS" — the one string the pill and the card both render.
    function label() {
        const s = Math.max(0, remaining)
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }

    //  ── controls ──────────────────────────────────────────────────
    //  start(minutes): arm a fresh session and run it immediately.
    function start(minutes) {
        totalSeconds = Math.max(1, Math.round(minutes * 60))
        remaining = totalSeconds
        running = true
    }

    //  setPreset(minutes): re-arm the dial while idle; ignored mid-run
    //  so a stray chip tap can never shorten a live session.
    function setPreset(minutes) {
        if (running)
            return
        totalSeconds = Math.max(1, Math.round(minutes * 60))
        remaining = totalSeconds
    }

    function toggle() {
        if (!running && remaining === 0)
            remaining = totalSeconds        //  finished session: run it again
        running = !running
    }

    function reset() {
        running = false
        remaining = totalSeconds
    }

    //  ── the tick ──────────────────────────────────────────────────
    Timer {
        id: tick
        interval: 1000
        running: focusTimer.running
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            focusTimer.remaining = Math.max(0, focusTimer.remaining - 1)
            if (focusTimer.remaining === 0) {
                focusTimer.running = false
                focusTimer.completions++
                Notifs.toast("Focus", "Session complete",
                    focusTimer.formatTotal() + " done — take a break")
            }
        }
    }

    function formatTotal() {
        const m = Math.round(totalSeconds / 60)
        return m >= 60 ? (Math.round(m / 60 * 10) / 10) + "h" : m + "m"
    }
}
