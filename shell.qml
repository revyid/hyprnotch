//  HyprNotch — macOS Dynamic Island style shell for Hyprland.
//
//  This file mounts the services (singletons load automatically on first
//  import), the island pill, the dock, the settings window, and the IPC
//  surface for keybinds. EVERYTHING interactive lives inside the island
//  window — control center, calendar, weather, notifications (banners
//  included), launcher, stats, wallpaper, power, about and plugins.

import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "services"
import "island"
import "dock"
import "panels"

ShellRoot {
    id: root

    Component.onCompleted: {
        //  Warm the services that probe hardware / network in the
        //  background: touching one property instantiates the singleton
        //  (the k4 warm-up trick), so the weather fetch and the
        //  NetworkManager/BlueZ connections start from the first frame.
        //  Hotkeys MUST be warmed too — its boot timers apply the chord
        //  map edited in Settings → Keybinds.
        Config.loaded = true
        void Weather.ready
        void Net.wifiEnabled
        void Bluetooth.available
        void SysMon.cpuPct
        void Power.profileAvailable
        void Wallpaper.available
        void Hotkeys.map
        void Clipboard.available
        console.log("[HyprNotch] started — config:", Config.filePath)
    }

    //  ── Windows ───────────────────────────────────────────────────
    //  ONE island hosts every interface including notification banners
    //  and the volume/brightness HUD (k4 style). Separate surfaces stay
    //  for what macOS also keeps separate: the dock and Settings.
    IslandWindow {}
    DockHost {}
    SettingsWindow {}

    //  ── IPC surface ───────────────────────────────────────────────
    //  Bind example (note the `ipc` subcommand — without it the bind
    //  fires nothing and the keypress falls through to the terminal):
    //    bind = SUPER, C, exec, quickshell ipc -p ~/.config/quickshell/hyprnotch/shell.qml call notch controlCenter
    //  services/Hotkeys.qml registers every chord from the map edited in
    //  Settings → Keybinds; `applyKeys` re-applies it after a manual
    //  hyprctl reload without relaunching the shell.
    IpcHandler {
        target: "notch"

        function controlCenter(): void { UiState.togglePopup("controlCenter") }
        function calendar(): void      { UiState.togglePopup("calendar") }
        function notifications(): void { UiState.togglePopup("notifCenter") }
        function closeAll(): void      { UiState.closeAll() }
        function launcher(): void      { UiState.togglePopup("launcher") }
        function weather(): void       { UiState.togglePopup("weather") }
        function stats(): void         { UiState.togglePopup("stats") }
        function wallpaper(): void     { UiState.togglePopup("wallpaper") }
        function power(): void         { UiState.togglePopup("power") }
        function about(): void         { UiState.togglePopup("about") }
        function plugins(): void       { UiState.togglePopup("plugins") }
        function containers(): void    { UiState.togglePopup("containers") }
        function agent(): void         { UiState.togglePopup("agent") }
        function clipboard(): void     { UiState.togglePopup("clipboard") }
        function features(): void {
            UiState.controlCenterPane = "features"
            UiState.openPopup("controlCenter")
        }
        //  alias: the quickToggles keybind action id resolves to the same pane
        function quickToggles(): void {
            UiState.controlCenterPane = "features"
            UiState.openPopup("controlCenter")
        }
        function screenshot(): void    { Power.screenshot() }
        function record(): void        { Power.record() }
        function settings(): void      { Power.openSettings() }
        function settingsPage(page: string): void { Power.openSettings(page) }
        function dock(): void          { Config.set("dock.enabled", !Config.data.dock.enabled) }
        function dnd(): void           { Notifs.toggleDnd() }
        function nightLight(): void    { Power.toggleNight() }
        function podman(): void        { UiState.togglePopup("containers") }
        function reloadPlugins(): void { Plugins.reload() }
        function applyKeys(): void     { Hotkeys.apply() }
    }
}
