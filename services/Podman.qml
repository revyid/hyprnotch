pragma Singleton

//  Podman container manager: list containers, start / stop / logs.
//  Talks `podman ps -a --format json`; if podman is missing the UI
//  shows a friendly empty state instead of crashing.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: podman

    property bool available: false
    property bool busy: false
    property var containers: []
    property string logs: ""
    property string logsFor: ""

    function refresh() {
        //  Feature gate (Settings → Containers → Enabled): the r23 round
        //  found the toggle was write-only — nothing respected it.
        if (!Config.get("podman.enabled", true)) {
            available = false
            containers = []
            return
        }
        lister.command = ["sh", "-c",
            "command -v podman >/dev/null && podman ps -a --format json 2>/dev/null || echo NOPDM"]
        lister.running = true
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOPDM") {
                    podman.available = false
                    podman.containers = []
                    return
                }
                podman.available = true
                try {
                    const rows = JSON.parse(text)
                    const out = []
                    for (let i = 0; i < rows.length; ++i) {
                        const r = rows[i]
                        out.push({
                            id: (r.Id || "").substring(0, 12),
                            names: Array.isArray(r.Names) ? r.Names[0] : (r.Names || "?"),
                            image: r.Image || "?",
                            state: r.State || r.Status || "?",
                            status: r.Status || ""
                        })
                    }
                    podman.containers = out
                } catch (e) {
                    podman.containers = []
                }
            }
        }
    }

    function start(id) {
        busy = true
        act.command = ["podman", "start", id]
        act.running = true
        Qt.callLater(refresh)
    }

    function stop(id) {
        busy = true
        act.command = ["podman", "stop", id]
        act.running = true
        Qt.callLater(refresh)
    }

    function restart(id) {
        busy = true
        act.command = ["podman", "restart", id]
        act.running = true
        Qt.callLater(refresh)
    }

    function fetchLogs(id) {
        logsFor = id
        logCmd.command = ["sh", "-c", `podman logs --tail 80 ${id} 2>&1`]
        logCmd.running = true
    }

    Process {
        id: logCmd
        stdout: StdioCollector {
            onStreamFinished: {
                podman.logs = text
                podman.busy = false
            }
        }
    }

    Process {
        id: act
        onExited: {
            busy = false
            podman.refresh()
        }
    }
}
