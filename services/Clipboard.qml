pragma Singleton

//  Clipboard history — the Win+V panel in the notch (r24).
//
//  Storage is cliphist (the wl-clipboard companion): start.sh launches
//  `wl-paste --watch cliphist store` once per session and everything
//  the user copies lands in cliphist's history database. This service
//  lists / re-copies / deletes / wipes those entries.
//
//  When cliphist or wl-clipboard is missing, `available` stays false
//  and the panel shows an honest install hint instead of an empty list.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: clipboard

    //  Feature gate (Settings → the quick-toggles panel → Clipboard).
    readonly property bool featureOn: Config.get("clipboard.enabled", true)
    readonly property bool available: featureOn
        && Power.bins["cliphist"] === true
        && Power.bins["wl-paste"] === true
        && Power.bins["wl-copy"] === true
    readonly property string missingTool: {
        if (!featureOn) return ""
        if (Power.bins["wl-paste"] !== true || Power.bins["wl-copy"] !== true)
            return "wl-clipboard"
        if (Power.bins["cliphist"] !== true) return "cliphist"
        return ""
    }

    property var entries: []            //  [{ idx, preview, binary }]
    property bool busy: false
    property string query: ""
    property int maxPreview: Config.get("clipboard.maxPreview", 90)

    //  ── list ──────────────────────────────────────────────────────
    //  `cliphist list` prints "N<TAB>preview"; N is the entry index
    //  that decode/delete accept. Binary entries look like
    //  "[[ binary data 25 KiB png ]]" — flag them so the UI can show
    //  a picture glyph instead of bracket soup.
    function refresh() {
        if (!available) {
            entries = []
            return
        }
        busy = true
        lister.command = ["sh", "-c", "cliphist list 2>/dev/null"]
        lister.running = true
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                clipboard.busy = false
                const rows = []
                const lines = text.split("\n")
                const cap = clipboard.maxPreview
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i]
                    if (line.length === 0)
                        continue
                    const tab = line.indexOf("\t")
                    if (tab < 1)
                        continue
                    const idx = line.substring(0, tab)
                    let preview = line.substring(tab + 1)
                    const binary = preview.indexOf("[[ binary data") === 0
                    if (!binary && preview.length > cap)
                        preview = preview.substring(0, cap) + "…"
                    rows.push({ idx: idx, preview: preview, binary: binary })
                }
                clipboard.entries = rows
            }
        }
    }

    //  ── paste back: decode → wl-copy ──────────────────────────────
    function copy(idx) {
        if (!available)
            return
        run("cliphist decode " + shellQuote(String(idx)) + " | wl-copy >/dev/null 2>&1")
        Notifs.toast("HyprNotch", "Copied to clipboard", "paste with Super+V anytime")
    }

    //  ── recall: copy back + type straight into the focused app ───
    //  The full Win+V flow (r26, "salin ulang + langsung ke paste"):
    //  one click puts the entry back on the clipboard AND types it
    //  into whatever window held focus before the island opened.
    //  wtype writes over the virtual-keyboard protocol — no daemon,
    //  and it works in terminals too (it is typing, not Ctrl+V).
    //  Sequencing matters: the island closes first, 0.22 s later
    //  Hyprland has handed focus back and the entry is typed; the
    //  toast is held until after that so its banner can never race
    //  the grab. Binary entries (images) only ever copy — typing
    //  bytes would just mangle them.
    function recall(idx) {
        if (!available)
            return
        let entry = null
        for (let i = 0; i < entries.length; ++i) {
            if (String(entries[i].idx) === String(idx)) {
                entry = entries[i]
                break
            }
        }
        if (entry && entry.binary) {
            copy(idx)
            return
        }
        const id = shellQuote(String(idx))
        run("cliphist decode " + id + " | wl-copy >/dev/null 2>&1")
        if (Power.bins["wtype"] !== true) {
            Notifs.toast("HyprNotch", "Copied to clipboard",
                         "install wtype for one-click paste (paru -S wtype)")
            return
        }
        UiState.closeAll()
        run("sleep 0.22; cliphist decode " + id + " | wtype - >/dev/null 2>&1")
        pasteToast.restart()
    }

    //  Fires after the paste window so the banner never steals focus
    //  mid-type.
    Timer {
        id: pasteToast
        interval: 800
        onTriggered: Notifs.toast("HyprNotch", "Pasted",
                                  "entry is back on the clipboard and typed out")
    }

    //  ── delete one / wipe all ─────────────────────────────────────
    function remove(idx) {
        if (!available)
            return
        busy = true
        actProc.command = ["sh", "-c", "cliphist delete " + shellQuote(String(idx)) + " 2>/dev/null"]
        actProc.running = true
    }

    function wipe() {
        if (!available)
            return
        busy = true
        actProc.command = ["sh", "-c", "cliphist wipe 2>/dev/null"]
        actProc.running = true
    }

    Process {
        id: actProc
        onExited: clipboard.refresh()
    }

    //  ── helpers ───────────────────────────────────────────────────
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd])
    }

    //  First open of the panel triggers a refresh; the availability
    //  flags come from Power's startup bin probe (no extra forks).
    property bool panelOpen: false
    onPanelOpenChanged: if (panelOpen) refresh()
}
