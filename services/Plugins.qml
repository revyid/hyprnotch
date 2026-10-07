pragma Singleton

//  Plugin host — user extensibility.
//
//  Drop a .qml file into ~/.config/quickshell/hyprnotch/plugins/ and it
//  becomes part of the island: a compact chip in the hover peek and a
//  full view inside the pill. The contract is 6 properties (see
//  plugins/README.md):
//
//      Item {
//          property string name: "My Plugin"
//          property string icon: "\uF00C"
//          property int prefWidth: 360
//          property bool enabled: true
//          property Component compact: Item { ... }   //  peek chip, ~20 px tall
//          property Component view: Item { ... }      //  island body view
//      }
//
//  Instances live here in an invisible container; the island binds to
//  `plugins` (descriptors) and instantiates compact/view Components
//  with Loaders. One instance per plugin = shared state between chip
//  and view (a pomodoro timer keeps running wherever it is displayed).
//
//  PluginApi (services) gives plugins exec / config / toast powers.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: pluginHost

    property var plugins: []             //  { url, name, icon, prefWidth, enabled, compact, view, root }
    property int revision: 0

    readonly property string dir: {
        const home = Quickshell.env("HOME") || ""
        return home + "/.config/quickshell/hyprnotch/plugins"
    }

    //  Disabled file names live in config so they survive restarts.
    function isDisabled(fileName) {
        const list = Config.get("plugins.disabled", [])
        return list.indexOf(fileName) >= 0
    }

    function setDisabled(fileName, disabled) {
        const list = Config.get("plugins.disabled", []).slice()
        const i = list.indexOf(fileName)
        if (disabled && i < 0) {
            list.push(fileName)
            Config.set("plugins.disabled", list)
        } else if (!disabled && i >= 0) {
            list.splice(i, 1)
            Config.set("plugins.disabled", list)
        }
        reload()
    }

    //  Visible-only model for the UI (peek chips, plugin row).
    readonly property var active: {
        const out = []
        for (let i = 0; i < plugins.length; ++i)
            if (plugins[i].enabled)
                out.push(plugins[i])
        return out
    }

    function open(idx) {
        if (idx < 0 || idx >= active.length)
            return
        UiState.openPopup("plugin:" + idx)
    }

    function descriptorForPopup(popupName) {
        if (popupName.indexOf("plugin:") !== 0)
            return null
        const idx = parseInt(popupName.substring(7))
        return (idx >= 0 && idx < active.length) ? active[idx] : null
    }

    //  ── discovery & instantiation ─────────────────────────────────
    function reload() {
        //  Tear down old instances first — editing a plugin then
        //  reloading must not resurrect the previous version.
        for (let i = 0; i < plugins.length; ++i) {
            try { plugins[i].root.destroy() } catch (e) { /* never existed */ }
        }
        plugins = []
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["sh", "-c", "mkdir -p '" + pluginHost.dir + "' && ls -1 '" + pluginHost.dir + "'/*.qml 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.trim().split("\n")
                for (let i = 0; i < rows.length; ++i) {
                    const path = rows[i].trim()
                    if (path.length > 0 && path.endsWith(".qml"))
                        pluginHost.loadFile(path)
                }
                pluginHost.revision += 1
            }
        }
    }

    function loadFile(path) {
        const fileName = path.substring(path.lastIndexOf("/") + 1)
        if (isDisabled(fileName))
            return

        const url = "file://" + path
        let comp = Qt.createComponent(url)
        if (comp.status === Component.Error) {
            console.warn("[Plugins] failed to load", fileName + ":", comp.errorString())
            return
        }
        let root = comp.createObject(container)
        if (!root) {
            console.warn("[Plugins] failed to instantiate", fileName + ":", comp.errorString())
            return
        }
        if (typeof root.name !== "string" || root.name.length === 0) {
            console.warn("[Plugins] skipping", fileName, "— no `name` property")
            root.destroy()
            return
        }
        plugins = plugins.concat([{
            url: url,
            file: fileName,
            name: root.name,
            icon: typeof root.icon === "string" && root.icon.length > 0 ? root.icon : "\uF00C",
            prefWidth: typeof root.prefWidth === "number" ? root.prefWidth : 380,
            enabled: true,
            compact: root.compact || null,
            view: root.view || null,
            root: root
        }])
    }

    Item {
        id: container
        visible: false
    }

    Component.onCompleted: reloadTimer.restart()

    Timer {
        id: reloadTimer
        interval: 800          //  after Config deep-merge has settled
        onTriggered: pluginHost.reload()
    }

    onPluginsChanged: revision += 1
}
