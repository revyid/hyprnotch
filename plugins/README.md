# HyprNotch Plugins

Drop a `.qml` file into this folder (`~/.config/quickshell/hyprnotch/plugins/`)
and it becomes part of the island: a chip in the hover peek and a full
view inside the pill. No registration, no rebuild — restart the shell
(`./start.sh`) or call the island's plugin row.

## The contract (6 properties)

```qml
import QtQuick
import "../core"
import "../services"

Item {
    readonly property string name: "My Plugin"     // shown on the chip
    readonly property string icon: "\uF252"        // Nerd Font glyph
    readonly property bool enabled: true           // gate on your own config if you like
    property Component compact: compactComp        // peek chip (~20 px tall Item)
    property Component view: viewComp              // island body view

    Component {
        id: compactComp
        Item {
            implicitHeight: 20
            // your mini UI — keep it one row
        }
    }

    Component {
        id: viewComp
        Item {
            property int prefWidth: 320            // island width while open
            implicitHeight: 150                    // island height while open
            // your full UI
        }
    }
}
```

Rules of the road:

- The root must be an `Item`. One instance is created per plugin and kept
  alive in a hidden container — state lives on the root, so the chip and
  the view share it (a timer keeps running wherever you look).
- `view`'s root MUST declare `prefWidth` and `implicitHeight`: the island
  springs to those numbers.
- Files that fail to load are skipped with a warning on the log — a bad
  plugin can never take the shell down.

## Your powers

Plugins import `../services`, so every shell service is available:

| Service | What you get |
|---------|--------------|
| `Notifs.toast(app, summary, body)` | push a banner through the island pipeline |
| `Config.get(path, fallback)` / `Config.set(path, value)` | persist state (`plugin.<name>.<key>` is the convention) |
| `Power.run(cmd)` | fire-and-forget shell command |
| `SysMon` | live CPU / RAM / network / battery + history arrays |
| `Media` | MPRIS playing / title / progress |
| `UiState.openPopup(name)` | open another island view |
| `Weather`, `Net`, `Bluetooth`, `Wallpaper` | realtime data services |

## Included samples

- **pomodoro.qml** — focus timer: peek chip shows the clock, the view has
  play/pause/reset, sessions announce themselves via `Notifs.toast`.
- **notes.qml** — one sticky note persisted to `plugin.notes.text`.

## Managing plugins

Disabled plugins live in `config.json` under `plugins.disabled` (file
names). To turn one off:

```sh
hyprnotch-config  # not needed — just edit ~/.config/hyprnotch/config.json
```

```json
{ "plugins": { "disabled": ["pomodoro.qml"] } }
```
