pragma Singleton

//  Bluetooth via BlueZ (Quickshell.Bluetooth) — fully realtime.
//
//  Same deal as Wi-Fi: discovery only runs while a view is actually
//  showing the device list (`discoveryWanted`). The adapter object
//  notifies on every change, so connect states, batteries and new
//  devices appear live with zero polling.
//
//  Pairing is the one thing the Quickshell API cannot do alone — it
//  publishes state but registers no pairing agent, so BlueZ drops the
//  bond after a couple of seconds. bluetoothctl DOES register an agent,
//  so the initial pairing is handed to it (scan → pair → trust →
//  connect), then the API takes over again for connect/disconnect.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"

Singleton {
    id: bt

    //  ── Adapter ──────────────────────────────────────────────────
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter ? adapter.enabled : false
    readonly property bool discovering: adapter ? adapter.discovering : false

    //  Set by the view showing the list; drives the adapter scanner.
    property bool discoveryWanted: false

    Binding {
        target: Bluetooth.defaultAdapter
        property: "discovering"
        value: bt.discoveryWanted
        when: Bluetooth.defaultAdapter !== null
    }

    //  ── Device list: connected → paired → alphabetical ──────────
    readonly property var devices: {
        if (!adapter)
            return []
        const list = adapter.devices.values.slice()
        list.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1
            return String(a.name).localeCompare(String(b.name))
        })
        return list
    }

    readonly property int connectedCount: {
        let n = 0
        for (let i = 0; i < devices.length; ++i)
            if (devices[i].connected)
                n++
        return n
    }

    //  ── Helpers ──────────────────────────────────────────────────
    function deviceIcon(device) {
        const icon = device && device.icon ? device.icon : ""
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return Icons.headphones
        if (icon.indexOf("phone") !== -1)    return Icons.phone
        if (icon.indexOf("mouse") !== -1)    return Icons.mouseIcon
        if (icon.indexOf("keyboard") !== -1) return Icons.keyboard
        if (icon.indexOf("speaker") !== -1 || icon.indexOf("audio") !== -1) return Icons.speaker
        if (icon.indexOf("watch") !== -1)    return Icons.watch
        if (icon.indexOf("gaming") !== -1 || icon.indexOf("joystick") !== -1) return Icons.gamepad
        if (icon.indexOf("computer") !== -1 || icon.indexOf("laptop") !== -1) return Icons.laptop
        if (icon.indexOf("printer") !== -1)  return Icons.printer
        if (icon.indexOf("video") !== -1 || icon.indexOf("tv") !== -1) return Icons.tv
        return Icons.devices
    }

    //  Who we are pairing right now, so the row can say so.
    property string pairingMac: ""
    property string pairFailedMac: ""

    function deviceStatus(device) {
        if (!device)
            return ""
        if (pairingMac === device.address)
            return "Pairing…"
        if (pairFailedMac === device.address && !device.paired)
            return "Could not pair"
        if (device.pairing)
            return "Pairing…"
        if (device.connected)
            return device.batteryAvailable
                ? "Connected · " + Math.round(device.battery * 100) + "%"
                : "Connected"
        if (device.paired || device.bonded)
            return "Paired"
        return "Available"
    }

    //  ── Actions ──────────────────────────────────────────────────
    function toggle() {
        if (adapter)
            adapter.enabled = !adapter.enabled
    }

    //  Pairing is NOT connecting, and without trust it does not last.
    //  Connect first, trust second: trusted devices rejoin on their own
    //  tomorrow when they come out of the case.
    function activate(device) {
        if (!device)
            return

        if (device.connected) {
            device.disconnect()
            return
        }

        if (device.paired || device.bonded) {
            if (!device.trusted)
                device.trusted = true
            device.connect()
            return
        }

        pairDevice(device)
    }

    //  ── Pairing via bluetoothctl (with a real agent) ─────────────
    //
    //  A brand new device: pair WITH an agent, which is what the plain
    //  API misses. bluetoothctl --agent KeyboardDisplay covers both the
    //  "just works" flow of headphones and the on-screen code of a
    //  keyboard or phone. The session pipes scan → pair → trust →
    //  connect through its stdin, with waits, exactly like doing it by
    //  hand — without discovery BlueZ answers "not available".
    function pairDevice(device) {
        if (!device || _agent.running)
            return
        //  The address goes into a shell command: verify it is a MAC and
        //  nothing else. It comes from BlueZ, but never trust input.
        const mac = String(device.address || "")
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac))
            return

        _recent = device
        pairingMac = mac
        pairFailedMac = ""

        _agent.command = ["sh", "-c",
            "{ echo 'scan on'; sleep 4;"
            + " echo 'pair " + mac + "'; sleep 9;"
            + " echo 'trust " + mac + "'; sleep 1;"
            + " echo 'connect " + mac + "'; sleep 7;"
            + " echo quit; } | bluetoothctl --agent KeyboardDisplay"]
        _agent.running = true
    }

    property var _recent: null

    Process {
        id: _agent
        running: false

        stdout: StdioCollector { }
        stderr: StdioCollector { }

        onExited: function (code, status) {
            const d = bt._recent
            bt.pairingMac = ""
            if (!d) {
                bt._recent = null
                return
            }
            //  Paired: trust and connect. If not, say so — hiding a
            //  failure here leaves the user poking a dead row.
            if (d.paired || d.bonded) {
                if (!d.trusted)
                    d.trusted = true
                bt._watch.rounds = 0
                bt._watch.restart()
            } else {
                bt.pairFailedMac = d.address
                bt._recent = null
            }
        }
    }

    //  Keep trying for a while: the FIRST connection is not the good one.
    //
    //  BlueZ opens a link while pairing and with many headphones that
    //  link falls off a couple of seconds after pairing completes. A
    //  connect() fired on seeing `paired` arrives while that link is
    //  still up, does nothing, and when the link dies nobody is left
    //  watching. So after pairing we watch for a few seconds and
    //  reconnect whenever it drops. Stop on rounds exhausted, NOT on the
    //  first "connected" — calling it done early is the exact bug.
    Timer {
        id: _watch
        property int rounds: 0

        interval: 1500
        repeat: true

        onTriggered: {
            const d = bt._recent
            rounds++
            if (!d || !(d.paired || d.bonded) || rounds > 6) {
                stop()
                bt._recent = null
                return
            }
            if (!d.connected)
                d.connect()
        }
    }
}
