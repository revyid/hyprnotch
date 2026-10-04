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
#  If mako / dunst / fnott / swaync / xfce4-notifyd already grabbed
#  org.freedesktop.Notifications, HyprNotch can't render banners in the
#  pill and you'd see the other daemon's toasts instead. We stop them,
#  their user services too (so DBus activation can't resurrect them
#  behind our back), and you should remove them from autostart:
#      exec-once mako        <- delete lines like this
for d in mako dunst fnott swaync xfce4-notifyd; do
    pkill -x "$d" 2>/dev/null
done
pkill -f xfce4-notifyd 2>/dev/null
systemctl --user stop dunst.service mako.service swaync.service \
    fnott.service xfce4-notifyd.service 2>/dev/null
echo "[HyprNotch] notification field cleared — HyprNotch IS the notification daemon now (banners render in the pill)"

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

#  ── Dock layer rules ─────────────────────────────────────────────
#  Runtime layer rules for the dock surface (namespace hyprnotch-dock):
#  compositor blur + hairline alpha handling under the frosted fallback,
#  no open/close animation (the dock animates itself). Applied via
#  `hyprctl keyword` so it works identically on mainline hyprland.conf
#  and the k4 Lua fork, and can never break a config parse. A manual
#  `hyprctl reload` clears them — restart the shell to re-apply.
#  Persistent alternative for hyprland.conf users (see sample file):
#    layerrule = blur, hyprnotch-dock
#    layerrule = ignorealpha 0.2, hyprnotch-dock
#    layerrule = noanim, hyprnotch-dock
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl keyword layerrule "blur, hyprnotch-dock" >/dev/null 2>&1 || true
    hyprctl keyword layerrule "ignorealpha 0.2, hyprnotch-dock" >/dev/null 2>&1 || true
    hyprctl keyword layerrule "noanim, hyprnotch-dock" >/dev/null 2>&1 || true
fi

echo "[HyprNotch] launching: $INSTALLED/shell.qml"
exec quickshell -p "$INSTALLED/shell.qml" "$@"
