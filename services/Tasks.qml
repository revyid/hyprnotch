pragma Singleton

//  Tiny task list, persisted to its own state file. Shows up inside the
//  control center (if enabled) — add, check off, delete. No bloat.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: tasks

    property var items: []

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") && Quickshell.env("XDG_STATE_HOME").length > 0)
        ? Quickshell.env("XDG_STATE_HOME") : homeDir + "/.local/state"
    readonly property string filePath: stateDir + "/hyprnotch/tasks.json"

    FileView { id: store; path: tasks.filePath; blockLoading: true }

    Process {
        command: ["mkdir", "-p", tasks.stateDir + "/hyprnotch"]
        running: true
        onExited: tasks.load()
    }

    function load() {
        const raw = store.text()
        if (raw && raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                items = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                items = []
            }
        }
    }

    function save() {
        try {
            store.setText(JSON.stringify(items, null, 1))
        } catch (e) { /* state file, not critical */ }
    }

    function add(text) {
        const t = (text || "").trim()
        if (t.length === 0)
            return
        const copy = items.slice()
        copy.push({ text: t, done: false, created: Date.now() })
        items = copy
        save()
    }

    function toggle(index) {
        if (index < 0 || index >= items.length)
            return
        const copy = JSON.parse(JSON.stringify(items))
        copy[index].done = !copy[index].done
        items = copy
        save()
    }

    function remove(index) {
        if (index < 0 || index >= items.length)
            return
        const copy = items.slice()
        copy.splice(index, 1)
        items = copy
        save()
    }

    function clearDone() {
        items = items.filter(i => !i.done)
        save()
    }
}
