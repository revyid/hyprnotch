# HyprNotch

A macOS Dynamic Island style shell for **Hyprland**, built from scratch on
[Quickshell](https://quickshell.outfoxxed.me) (QML). 100% English code and UI,
deeply configurable, fully extensible — one JSON config drives everything,
and a QML plugin system lets you add your own features.

## The one-island architecture (k4 style)

Everything lives INSIDE the pill. The island is a single full-screen layer
surface that never resizes; the island body animates inside it with the
k4 spring (`OutBack`, width 440 ms / height 400 ms) and melts into the screen
edge with inverted-corner wings. Control Center, Calendar, Weather, Stats,
Wallpaper, Power, About, Notification Center, Launcher and plugin views are
all hosted as views of the same body — one occupant at a time, ESC closes,
a click outside closes, and the input mask follows the island's animated
geometry so the desktop underneath stays fully clickable wherever the island
is not.

### The four morph states

1. **compact** — clock + date, weather, smart workspaces, status glyphs.
2. **peek (hover)** — brush the pill and it springs open: media mini with
   live progress, your two most recent notifications, live CPU/RAM bars +
   network rate, and one chip per installed plugin. Every row is a shortcut
   into its full view.
3. **hud** — volume or brightness keys morph the pill into a slider bar for
   a moment, then it folds back. Fully inside the pill, from any source.
4. **expanded** — a full card (one at a time): control center, calendar,
   weather menu, stats with live charts, wallpaper picker, power menu,
   notifications, launcher, about, or a plugin.

## Features

- **Island pill** — clock + date (click opens the **calendar** inside the
  island), live **weather** (opens the weather menu), **smart workspaces**
  (empty desktops never show — 1 active workspace = 1 pill, the cap is
  configurable via `island.maxVisibleWorkspaces`, overflow shows `+N`),
  status indicators (audio, mic, network with real signal strength,
  battery — clicking it opens the **power menu**), unseen-notifications
  bell. Pressing **Super+Space** opens the **command-palette launcher**
  (every island action + every app, fully keyboard-driven).
- **Wi-Fi manager (realtime)** — live network list via NetworkManager:
  signal bars, lock icons, connect/disconnect with a single click, inline
  password form for secured networks, radio toggle, rescan. The scanner
  only runs while the list is open.
- **Bluetooth manager (realtime)** — live device list via BlueZ with
  category icons and battery levels, connect/disconnect, and real pairing
  through a bluetoothctl agent (scan → pair → trust → connect) with
  auto-reconnect watchdog.
- **Weather menu (realtime)** — big current conditions, feels-like,
  humidity/wind chips, 7-slot hourly strip, 5-day outlook and a city
  switcher (geocoding search) — Open-Meteo, no API key.
- **System Stats (dedicated, with charts)** — no longer buried in the
  control center: a full monitor view with live Canvas graphs (CPU,
  memory, auto-scaling network), a per-core strip, disk and swap cards,
  temperature and uptime chips. Data flows from two long-running probes
  (2 s system loop + 1 s network loop), 60 samples of history each.
- **Control Center (inside the island)** — connection tiles (Wi-Fi and
  Bluetooth open their manager panes, DND and night light toggle in place),
  weather, brightness + volume sliders, mic mute, MPRIS media card with a
  live progress bar, **quick actions**, and a mini **task list**.
- **Power & battery (one menu)** — battery ring gauge with live % and
  watts, **Energy Mode** segmented control (Low Power / Balanced / High
  Power via powerprofilesctl), and a session grid: Lock, Sleep, Logout,
  Restart, Shut Down — destructive ones use macOS **hold-to-confirm**
  (a ring fills while you hold; release early = nothing happens).
  Plus an "About This Machine" entry.
- **About This Machine** — macOS "About This Mac" aesthetic: logo halo,
  hostname, distro, and staggered-reveal spec rows (chip, graphics,
  memory, startup disk, kernel, uptime, desktop) fed live by the SysMon
  identity probe.
- **Wallpaper picker (awww / swww)** — scans ~/Pictures, Downloads and the system
  wallpaper dirs (custom dir configurable), real thumbnail grid, one tap
  applies with a live transition (grow / outer / wipe / fade / simple /
  random, duration configurable), check badge on the current one. The
  tool is auto-detected: awww (Omarchy-style fork) preferred, swww as
  fallback.
- **Quick actions** — built-ins (DND, night light, screenshot, record,
  terminal, files, wallpaper, stats, power, about, lock, settings) plus
  unlimited custom shell-command actions.
- **Dock (real macOS anatomy)** — **real application icons** resolved
  through the system icon theme and .desktop entries (three-pass match:
  icon name → lowercase → DesktopEntries), soft drop shadows, no tiles,
  neighbor-falloff magnification, launch **bounce**, press squish, running
  dots under icons (white = focused), hover tooltips, frosted glass shelf.
  Pinned apps are `.desktop` ids (legacy glyph pins still work); running
  unpinned apps join the dock automatically; clicking a pinned app focuses
  it if running, otherwise launches it via its desktop entry.
- **Notifications (HyprNotch IS the daemon)** — Quickshell's
  NotificationServer claims org.freedesktop.Notifications, so banners
  render INSIDE the island window under the pill: app icon, summary, body,
  action buttons, per-banner lifetime paused on hover, click-to-activate.
  DND keeps everything silently in history. `start.sh` kills mako/dunst/
  fnott/swaync so HyprNotch always wins the D-Bus name — remove them from
  your own autostart too. The notification center lists everything with
  icons and actions.
- **HUD (inside the pill)** — volume/brightness morph state, driven from
  any source (keys, scrolls, other apps).
- **Launcher = command palette (inside the island)** — opens on
  **Super+Space** (rebindable in Settings → Keybinds). One search box
  over EVERYTHING: every island action (control center, calendar,
  notifications, weather, stats, wallpaper, power, about, plugins,
  settings, DND, containers, night light, dock, plugin reload,
  keybind re-apply) plus all installed apps with real icons. Each
  action row shows its live chord from Settings → Keybinds. Arrow
  keys / PageUp / PageDown move, Enter runs, Esc closes — the whole
  notch is drivable without touching the mouse.
- **Plugins** — drop a `.qml` file into `plugins/` and the island gains a
  peek chip + a full view. Two samples included (Pomodoro, Notes). See
  `plugins/README.md` for the 6-property contract and the service API
  plugins can use.
- **Settings window** — the classic deep-configuration surface: island
  toggles/sizes, control-center sections (reorder/enable/resize), quick
  actions editor, dock pins and behavior, calendar, notifications, HUD,
  launcher, tasks, Podman manager, Hermes agent.

## Install / run

```sh
# deps (Arch): quickshell, hyprland, nerd font (MesloLGS NF), awww or swww (optional)
tar xf hyprnotch-v1.zip && cd hyprnotch
./start.sh
```

`start.sh` syncs this folder into `~/.config/quickshell/hyprnotch` (so the
downloaded copy is always what runs), stops other notification daemons,
and launches the shell.

### Keybinds

Three ways, pick any:

1. **Zero config (default)** — `services/Hotkeys.qml` applies the chord map
   ~1.5 s after the shell starts (and re-asserts once more at ~5.5 s, the
   k4 fork can wipe runtime binds by re-applying its config async). Keys
   held by YOUR other binds are never hijacked. Binds die on a manual
   `hyprctl reload`; re-apply with
   `quickshell ipc -p ~/.config/quickshell/hyprnotch/shell.qml call notch applyKeys`
   or re-run start.sh.
2. **Classic config** — append `sample-hyprland.conf` to your
   `hyprland.conf` (the installer does it for you on request).
3. **k4 Lua fork** (`~/.config/hypr/hyprland.lua`) — the installer writes
   `~/.config/hypr/config/hyprnotch.lua` (an `hl.bind` template) and hooks
   `require("config.hyprnotch")` into your `hyprland.lua`. Revert = delete
   both. The same trick the k4 installer uses.

**Every chord is editable live** in Settings → Keybinds: click Edit, press
the new combination, save. Saving unbinds the old Notch bind, registers
the new one, and rewrites `hyprnotch.lua` on k4 Lua forks so the edit
survives reloads. Factory chords: Super+Space launcher, Super+C control
center, Super+T stats, and friends.

Highlights (see `sample-hyprland.conf` for all):

```conf
bind = SUPER, SPACE, exec, $notch launcher    # launcher (was Super-tap till r14)
bind = SUPER, C, exec, $notch controlCenter   # control center
bind = SUPER, K, exec, $notch calendar        # calendar
bind = SUPER, W, exec, $notch weather         # weather menu
bind = SUPER, T, exec, $notch stats           # system stats
bind = SUPER, G, exec, $notch wallpaper       # wallpaper picker
bind = SUPER, I, exec, $notch about           # about this machine
bind = SUPER, O, exec, $notch plugins         # plugin menu
```

Every view is also reachable via IPC (note the `ipc` subcommand — without
it the command silently does nothing):
`quickshell ipc -p ~/.config/quickshell/hyprnotch/shell.qml call notch <name>` —
names: `controlCenter`, `calendar`, `notifications`, `launcher`, `weather`,
`stats`, `wallpaper`, `power`, `about`, `settings`, `dnd`, `nightLight`,
`podman`, `agent`, `reloadPlugins`, `applyKeys`, `closeAll`.

## Configuration

Everything persists at `~/.config/hyprnotch/config.json` and applies live.
Notable keys: `island.maxVisibleWorkspaces`, `island.peekEnabled`,
`wallpaper.dir/transition/duration`, `dock.pinned` (desktop ids or legacy
glyph pins), `plugins.disabled`, `quickActions`, `controlCenter.sections`,
`hypr.luaDispatch` (default `true` — quote dispatch args for the k4 Lua
fork; set to `false` on mainline Hyprland).

### Where things live

- **System stats** — `Super+T`, the CPU/RAM row in the hover peek, the
  "System Stats" quick action, or the battery chip → power menu → About.
- **Plugins menu** — `Super+O`, or Control Center → Plugins → Manage.
  Toggle, open, and reload plugins; drop new `.qml` files into
  `~/.config/quickshell/hyprnotch/plugins/` and press refresh.
- **Keybinds** — Settings → Keybinds edits every chord live (capture a
  combo, save, done); `sample-hyprland.conf` defines the `$notch` variable
  so every island view is also bindable by hand; `install.sh` can append
  them for you.

## Development & testing

The repo ships its own static analysis suite so you can develop without a
Qt toolchain installed — plain Python 3 is enough:

```sh
./scripts/test.sh                    # run the QML sanity checks
python3 scripts/check_hyprnotch.py   # same thing, called directly
```

`scripts/check_hyprnotch.py` (v14) parses every `.qml` file in the repo and
catches the entire class of Quickshell/QML breakages hit while building this
shell: unbalanced braces, missing imports (including types pulled from the
wrong module — e.g. ScrollIndicator without QtQuick.Controls), assignments to
non-existent or read-only properties, `Behavior on` a read-only target,
invalid PanelWindow root properties (opacity, etc.), nested `WlrLayershell`
enum use (must be standalone `WlrKeyboardFocus`), singleton member
references, handler/property mismatches, duplicate ids, duplicate signal
handlers, arrow-if bodies, never-started probe loops, and Images decoding
model data without `sourceSize` (the OOM class). Run it before every commit —
if it passes, the shell starts.

Suggested loop when hacking on the shell:

```sh
./scripts/test.sh && ./start.sh   # verify, then sync + relaunch live
```

## License

Released under the [MIT License](LICENSE).
