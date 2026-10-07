pragma Singleton

//  Wi-Fi via NetworkManager (Quickshell.Networking) — fully realtime.
//
//  The scanner only runs while a view is actually showing the network
//  list (`scanning`): leaving it on wastes radio and battery for nothing.
//  Every consumer binds straight to the same objects NetworkManager
//  notifies, so signal strength, connection state and the current SSID
//  update live with zero polling.

import QtQuick
import Quickshell
import Quickshell.Networking
import "../core"

Singleton {
    id: net

    //  ── The radio switch ─────────────────────────────────────────
    //  A plain mirror: NetworkManager is the source of truth. The
    //  Connections sync keeps it live even when something else flips
    //  the radio (nmcli, another applet) — a declarative binding here
    //  would be destroyed the first time the UI writes it imperatively.
    property bool wifiEnabled: false

    Connections {
        target: Networking
        ignoreUnknownSignals: true
        function onWifiEnabledChanged() { net.wifiEnabled = Networking.wifiEnabled }
    }

    Component.onCompleted: net.wifiEnabled = Networking.wifiEnabled

    //  ── Reactive connection state (no polling, ever) ─────────────
    readonly property var wifiDevice: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i)
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        return null
    }

    //  SSID of the network currently connected, "" when none.
    readonly property string wifiSsid: {
        const dev = wifiDevice
        if (!dev)
            return ""
        const list = dev.networks.values
        for (let i = 0; i < list.length; ++i)
            if (list[i].connected)
                return list[i].name
        return ""
    }

    //  Signal level of the connected network (0..4) for the pill icon.
    readonly property int connectedLevel: {
        const dev = wifiDevice
        if (!dev)
            return 0
        const list = dev.networks.values
        for (let i = 0; i < list.length; ++i)
            if (list[i].connected)
                return strengthLevel(list[i])
        return 0
    }

    //  Wired carrier: an ethernet device that is up.
    readonly property bool wired: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i)
            if (devices[i].type === DeviceType.Ethernet && devices[i].connected)
                return true
        return false
    }

    //  ── Network list, sorted the way people expect it ────────────
    //  connected → known → strongest signal.
    readonly property var networks: {
        const dev = wifiDevice
        if (!dev)
            return []
        const list = dev.networks.values.slice()
        list.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.known !== b.known)
                return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return list
    }

    //  Set by whichever view is showing the list; cleared when closed.
    property bool scanning: false

    Binding {
        target: net.wifiDevice
        property: "scannerEnabled"
        value: net.scanning
        when: net.wifiDevice !== null
    }

    //  ── Password flow ────────────────────────────────────────────
    property var pskTarget: null     //  network waiting for a password
    property string pskInput: ""
    property string notice: ""

    //  ── Helpers ──────────────────────────────────────────────────
    function strengthLevel(network) {
        const s = network && network.signalStrength ? network.signalStrength : 0
        if (s >= 0.75) return 4
        if (s >= 0.5)  return 3
        if (s >= 0.25) return 2
        if (s > 0)     return 1
        return 0
    }

    function strengthIcon(network) {
        const lvl = strengthLevel(network)
        const icons = [Icons.wifi0, Icons.wifi1, Icons.wifi2, Icons.wifi3, Icons.wifi4]
        return icons[lvl]
    }

    function isSecure(network) {
        if (!network)
            return false
        //  Open and Owe (Enhanced Open) never ask for credentials.
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }

    //  connectWithPsk only works for these; EAP/enterprise networks need a
    //  NetworkManager profile, so plain connect() is tried there instead.
    function needsPsk(network) {
        if (!network)
            return false
        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae
    }

    function statusText(network) {
        if (!network)
            return ""
        if (network.stateChanging)
            return network.connected ? "Disconnecting…" : "Connecting…"
        if (network.connected)
            return "Connected"
        if (network.known)
            return "Saved"
        return isSecure(network) ? "Secured" : "Open"
    }

    //  ── Actions ──────────────────────────────────────────────────
    function activate(network) {
        if (!network)
            return

        notice = ""

        if (network.connected) {
            network.disconnect()
            return
        }

        if (network.known || !needsPsk(network)) {
            network.connect()
            return
        }

        //  Secured network with no stored credentials: ask for a password.
        pskInput = ""
        pskTarget = network
    }

    function submitPsk() {
        const network = pskTarget
        if (!network)
            return
        if (pskInput.length > 0)
            network.connectWithPsk(pskInput)
        pskInput = ""
        pskTarget = null
    }

    function cancelPsk() {
        pskInput = ""
        pskTarget = null
    }

    function toggleWifi() {
        //  Write straight to NetworkManager; its change notification
        //  loops back and updates the mirror through Connections.
        Networking.wifiEnabled = !Networking.wifiEnabled
    }

    //  Force a fresh scan burst (rescan button).
    function rescan() {
        scanning = false
        scanning = true
    }
}
