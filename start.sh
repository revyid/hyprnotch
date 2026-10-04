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
    for item in core services island dock panels plugins shell.qml README.md sample-hyprland.conf VERSION start.sh; do
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

#  ── Runtime keybinds (works on EVERY Hyprland, k4 Lua fork included) ──
#  Registers the island binds via `hyprctl keyword` so Super+C / Super+T /
#  ... work even when the installer could not touch the user's config
#  (no hyprland.conf, or a Lua-fork config we don't dare edit).
#  - Only runs inside a live Hyprland session.
#  - Keys that are ALREADY bound with Super are skipped — we never hijack
#    your own chords (e.g. k4's Super+L lock stays yours).
#  - Runtime binds die on `hyprctl reload` — re-running start.sh (or
#    logging in again) re-registers them. Persist them with
#    sample-hyprland.conf or hyprnotch.lua if you prefer.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    NOTCH_IPC="quickshell ipc -p $INSTALLED/shell.qml call notch"
    #  One bind object per line, so a line is exactly one bind: the key and
    #  its modmask can be matched together, never across entries.
    TAKEN="$(hyprctl -j binds 2>/dev/null | sed 's/},{/}\n{/g' || true)"

    #  taken <key> — reads bind JSON lines on stdin, exits 0 when that key
    #  is bound under Super (bit 64).  Every line after the sed split is
    #  exactly ONE bind object, so key and modmask are matched together,
    #  never across entries.  Bias: when in doubt we LEAVE the key alone —
    #  a skipped bind is visible in this log, a hijacked chord is worse.
    taken() {
        awk -v k="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '
            {
                line = tolower($0)
                if (match(line, /"key"[ \t]*:[ \t]*"[^"]*"/)) {
                    seg = substr(line, RSTART, RLENGTH)
                    gsub(/^"key"[ \t]*:[ \t]*"/, "", seg)
                    gsub(/"$/, "", seg)
                    if (seg == k) {
                        m = 0
                        if (match(line, /"modmask"[ \t]*:[ \t]*[0-9]+/)) {
                            mseg = substr(line, RSTART, RLENGTH)
                            gsub(/[^0-9]/, "", mseg)
                            m = mseg + 0
                        }
                        if (int(m / 64) % 2 == 1)
                            found = 1
                    }
                }
            }
            END { if (found) exit 0; exit 1 }
        '
    }
    bind_lines() { hyprctl -j binds 2>/dev/null | sed 's/},{/}\n{/g' || true; }

    reg() {
        #  reg <flag> <key> <ipc-function>
        _flag="$1"; _key="$2"; _fn="$3"
        if printf '%s\n' "$TAKEN" | taken "$_key"; then
            echo "[HyprNotch] bind SUPER+$_key already taken — left untouched"
            return 0
        fi
        hyprctl keyword "$_flag SUPER,$_key,exec,$NOTCH_IPC $_fn" >/dev/null 2>&1 \
            && echo "[HyprNotch] bind SUPER+$_key -> notch $_fn" \
            || echo "[HyprNotch] bind SUPER+$_key FAILED (hyprctl keyword)"
    }

    reg bindr SUPER_L launcher     # Super tap: release bind, tap alone = launcher
    reg bind  C controlCenter
    reg bind  K calendar
    reg bind  N notifications
    reg bind  D launcher
    reg bind  W weather
    reg bind  T stats
    reg bind  G wallpaper
    reg bind  E power
    reg bind  I about
    reg bind  O plugins
    reg bind  S settings
    reg bind  B dnd
    reg bind  P podman

    #  ── Super-tap insurance ────────────────────────────────────────
    #  The k4 Lua fork re-applies its own bind set asynchronously, which
    #  can wipe runtime `hyprctl keyword` binds registered a moment
    #  earlier — Super-tap then silently dies while the chord binds from
    #  hyprnotch.lua keep working.  So 2 s after launch, re-check and
    #  re-assert the Super_L release bind ONLY if it is really gone
    #  (registering twice would make one tap toggle the island twice).
    (
        sleep 2
        if bind_lines | taken SUPER_L; then
            echo "[HyprNotch] super-tap bind verified live"
        else
            if hyprctl keyword "bindr SUPER,SUPER_L,exec,$NOTCH_IPC launcher" >/dev/null 2>&1; then
                echo "[HyprNotch] super-tap bind had been wiped — re-asserted"
            else
                echo "[HyprNotch] WARNING: super-tap did not stick. Add this line to your"
                echo "           Hyprland config:  bindr = SUPER, SUPER_L, exec, $NOTCH_IPC launcher"
            fi
        fi
    ) &

    unset -f reg taken bind_lines
fi

echo "[HyprNotch] launching: $INSTALLED/shell.qml"
exec quickshell -p "$INSTALLED/shell.qml" "$@"
