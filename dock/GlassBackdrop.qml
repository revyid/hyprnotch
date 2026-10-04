import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../core"
import "../services"

//  Liquid Glass BACKDROP — what the dock's shader refracts.
//
//  An invisible Item in screen coordinates (one per dock window) holding:
//    · the current wallpaper, cropped to fill the monitor
//    · one LIVE capture (ScreencopyView) per mapped window that actually
//      reaches the dock strip — floating windows stack above tiled ones
//
//  Captures are per-window, never a screen grab, so the dock can never
//  end up refracting itself.  Geometry comes from `hyprctl -j clients`
//  (the only source of window rectangles on Hyprland), each entry matched
//  to its capturable Quickshell toplevel by address.  Technique ported
//  from 0-ss/Swift-Dock.
//
//  Origin contract: this Item's top-left is the SCREEN's top-left.  The
//  host window (a bottom strip) offsets it by -(screenH - winH), so
//  client x/y from hyprctl can be used verbatim.

Item {
    id: backdrop

    //  ── Host wiring ───────────────────────────────────────────────
    property real screenW: 1920
    property real screenH: 1080
    property string screenName: ""
    property bool live: false            // master switch (dock visible + glass ready)
    property real zoneTop: 0             // dock strip top (screen coords) minus margin

    width: screenW
    height: screenH

    //  ── Placeholder while nothing is composited yet ───────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#2f6bff" }
            GradientStop { position: 0.5; color: "#b44cff" }
            GradientStop { position: 1.0; color: "#ff8a3d" }
        }
    }

    //  ── The wallpaper behind everything ───────────────────────────
    Image {
        anchors.fill: parent
        visible: status === Image.Ready
        source: visible ? Wallpaper.current : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: Math.ceil(backdrop.screenW)
        smooth: true
    }

    //  ── Live windows ──────────────────────────────────────────────
    ListModel { id: wm }

    Repeater {
        model: wm

        delegate: Item {
            id: gw

            required property string addr
            required property real wx
            required property real wy
            required property real ww
            required property real wh
            required property real wz

            x: wx
            y: wy
            width: ww
            height: wh
            z: wz

            //  Re-resolve the capturable toplevel whenever the window
            //  set changes (toplevels appear/disappear out of band).
            readonly property var tl: {
                wmVersion
                return backdrop.toplevelFor(addr)
            }

            ScreencopyView {
                anchors.fill: parent
                captureSource: gw.tl ? gw.tl.wayland : null
                live: backdrop.live
            }
        }
    }

    //  Bump to force every delegate to re-resolve its toplevel.
    property int wmVersion: 0

    function toplevelFor(addr) {
        const a = String(addr).replace(/^0x/, "")
        const ts = Hyprland.toplevels.values
        for (let i = 0; i < ts.length; ++i)
            if (String(ts[i].address) === a)
                return ts[i]
        return null
    }

    //  ── Client geometry polling ───────────────────────────────────
    //  Only while the glass is live: hyprctl -j clients is the sole
    //  source of window rectangles on Hyprland.
    readonly property bool polling: live

    Timer {
        id: pollTimer
        interval: 1500
        running: backdrop.polling
        repeat: true
        triggeredOnStart: false
        onTriggered: clientProc.running = true
    }

    onLiveChanged: if (live) clientProc.running = true

    Process {
        id: clientProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { backdrop.syncClients(JSON.parse(text)) }
                catch (err) { console.warn("glass: clients parse failed:", err) }
            }
        }
    }

    function syncClients(clients) {
        if (!clients || clients.length === undefined)
            return

        //  Which workspace is the dock's monitor showing right now?
        let wsId = -999
        const mons = Hyprland.monitors.values
        for (let m = 0; m < mons.length; ++m)
            if (mons[m].name === screenName && mons[m].activeWorkspace) {
                wsId = mons[m].activeWorkspace.id
                break
            }

        const want = {}
        for (let c = 0; c < clients.length; ++c) {
            const cl = clients[c]
            if (!cl.mapped || cl.hidden)
                continue
            if (cl.monitorName !== screenName || !cl.workspace
                || cl.workspace.id !== wsId)
                continue
            const x = cl.at[0], y = cl.at[1]
            const w = cl.size[0], h = cl.size[1]
            if (x + w <= 0 || x >= screenW || y + h <= zoneTop || y >= screenH)
                continue                      // never reaches the dock strip
            //  floating on top; most recently focused floating highest
            const z = cl.floating ? 100 - Math.min(cl.focusHistoryID || 0, 90) : 0
            want[cl.address] = {
                addr: cl.address, wx: x, wy: y, ww: w, wh: h, wz: z
            }
        }

        //  In-place update: keep delegates (and their captures) alive
        //  across polls instead of rebuilding the whole set.
        for (let j = wm.count - 1; j >= 0; --j) {
            const a = wm.get(j).addr
            if (want[a] === undefined) {
                wm.remove(j)
            } else {
                const u = want[a]
                wm.set(j, u)
                delete want[a]
            }
        }
        for (const k in want)
            wm.append(want[k])
        wmVersion++
    }
}
