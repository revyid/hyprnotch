#!/bin/sh
#  HyprNotch launcher — ALWAYS syncs this folder into
#  ~/.config/quickshell/hyprnotch, then launches the installed copy.
#
#  This means `./start.sh` can never run a stale build: whatever is in
#  the folder you downloaded is exactly what gets launched.

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLED="$HOME/.config/quickshell/hyprnotch"

BUILD="$(cat "$HERE/VERSION" 2>/dev/null || echo 'v1')"

command -v quickshell >/dev/null 2>&1 || {
    echo "[HyprNotch] ERROR: 'quickshell' not found in PATH."
    echo "           Install it first (Arch: paru -S quickshell-git)."
    exit 1
}

#  ── HyprNotch IS the notification daemon ─────────────────────────
#  If mako / dunst / fnott / swaync already grabbed
#  org.freedesktop.Notifications, HyprNotch can't render banners in the
#  pill and you'd see the other daemon's toasts instead. Remove them
#  from your Hyprland autostart too:
#      exec-once mako        <- delete lines like this
if pgrep -x mako >/dev/null 2>&1 || pgrep -x dunst >/dev/null 2>&1 \
   || pgrep -x fnott >/dev/null 2>&1 || pgrep -x swaync >/dev/null 2>&1; then
    pkill -x mako 2>/dev/null
    pkill -x dunst 2>/dev/null
    pkill -x fnott 2>/dev/null
    pkill -x swaync 2>/dev/null
    echo "[HyprNotch] stopped other notification daemons (mako/dunst/...) — HyprNotch renders banners in the pill now"
fi

#  ── State directories ────────────────────────────────────────────
#  Config store and task list live outside the config folder; make
#  sure both exist so FileView never warns on a fresh install.
mkdir -p "$HOME/.config/hyprnotch" "$HOME/.local/state/hyprnotch"
[ -f "$HOME/.local/state/hyprnotch/tasks.json" ] || printf '[]' > "$HOME/.local/state/hyprnotch/tasks.json"

#  ── Auto-install: refresh the installed copy from THIS folder ─────
if [ "$HERE" != "$INSTALLED" ]; then
    mkdir -p "$INSTALLED"
    SYNC_FAIL=0
    for item in core services island dock panels plugins scripts shell.qml README.md sample-hyprland.conf VERSION start.sh; do
        [ -e "$HERE/$item" ] || continue
        rm -rf "$INSTALLED/$item"
        if ! cp -r "$HERE/$item" "$INSTALLED/$item" 2>/dev/null; then
            echo "[HyprNotch] WARNING: could not sync '$item' — launching may use older files"
            SYNC_FAIL=1
        fi
    done
    chmod +x "$INSTALLED/start.sh" 2>/dev/null
    if [ "$SYNC_FAIL" -eq 0 ]; then
        echo "[HyprNotch] build $BUILD synced -> $INSTALLED"
    fi
else
    #  Running the installed copy directly — nothing to sync.
    echo "[HyprNotch] build $BUILD (installed copy)"
fi

#  ── Keybinds are NOT registered here anymore ─────────────────────
#  Since r15 the shell itself owns its chords: services/Hotkeys.qml
#  applies the map edited in Settings → Keybinds ~1.5 s after launch
#  (then re-asserts once at ~5.5 s — the k4 fork re-applies its config
#  asynchronously and can wipe runtime binds registered a moment
#  earlier). Only binds carrying our IPC signature are ever unbound,
#  so your own chords are never touched. Launcher default: Super+Space.
#  After a manual `hyprctl reload`, re-apply without relaunching:
#    quickshell ipc -p <installed>/shell.qml call notch applyKeys

echo "[HyprNotch] launching: $INSTALLED/shell.qml"
exec quickshell -p "$INSTALLED/shell.qml" "$@"
