#!/bin/sh
#  HyprNotch doctor — one honest page about the machine we run on.
#
#  Answers "kenapa X gabisa" without opening a single QML file:
#  every optional tool is listed with the feature that needs it, the
#  session services are checked, the MPRIS players are enumerated
#  (the #1 reason the cava spectrum "gabisa" is zero MPRIS players),
#  and the tail of the running shell log is printed so the last
#  runtime errors are right there on the same page.
#
#  Run: ./start.sh doctor   (or sh scripts/doctor.sh)

B="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$B/VERSION" 2>/dev/null || echo unknown)"

ok()   { printf " \033[32m ok \033[0m %s\n" "$1"; }
bad()  { printf " \033[31mMISS\033[0m %s\n" "$1"; }
warn() { printf " \033[33mwarn\033[0m %s\n" "$1"; }
hdr()  { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

echo "HyprNotch doctor — build $VERSION"

hdr "Session"
if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    ok "Hyprland session (sig $HYPRLAND_INSTANCE_SIGNATURE)"
else
    warn "HYPRLAND_INSTANCE_SIGNATURE empty — hyprctl calls will fail"
fi
if command -v quickshell >/dev/null 2>&1; then
    ok "quickshell $(quickshell --version 2>/dev/null | head -1)"
else
    bad "quickshell not in PATH — nothing can launch"
fi
if command -v hyprctl >/dev/null 2>&1; then
    ok "hyprctl ($(hyprctl version 2>/dev/null | head -1))"
else
    bad "hyprctl — the shell cannot talk to the compositor"
fi

hdr "Optional tools (feature: tool)"
probe() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$2: $1"
    else
        bad "$2: $1 missing"
    fi
}
probe playerctl       "media card + transport keys + MPRIS status"
probe cava            "audio spectrum (real frames; synth fallback without it)"
probe wtype           "clipboard one-click paste (types the entry for you)"
probe cliphist        "clipboard history store"
probe wl-copy         "clipboard copy"
probe wl-paste        "clipboard read + store daemon"
probe grimblast       "screenshots (all-in-one)"
probe grim            "screenshots (fallback)"
probe slurp           "screenshots (region select)"
probe wf-recorder     "screen recording"
probe hyprsunset      "night light"
probe brightnessctl   "brightness keys"
probe nmcli           "wifi / network list"
probe powerprofilesctl "power profile switcher"
probe podman          "containers manager"
probe awww            "wallpaper daemon"

hdr "MPRIS players (the media card AND the cava spectrum need one)"
if command -v playerctl >/dev/null 2>&1; then
    if playerctl -l 2>/dev/null | grep -q .; then
        playerctl -l 2>/dev/null | sed 's/^/  player: /'
        playerctl status 2>/dev/null | sed 's/^/  status: /'
    else
        warn "no MPRIS player at all — the spectrum stays flat and the"
        warn "media card is empty. Players count only if they expose"
        warn "MPRIS (browsers need their media-keys / Plasma integration"
        warn "extension; mpv needs --script=mpv-mpris; spotify ships it)."
    fi
else
    bad "playerctl missing — cannot enumerate players"
fi

hdr "Notification field (HyprNotch IS the daemon)"
found=0
for d in mako dunst fnott swaync xfce4-notifyd; do
    if pgrep -x "$d" >/dev/null 2>&1; then
        warn "$d is RUNNING — it steals banners from the island (pkill $d)"
        found=1
    fi
done
[ "$found" -eq 0 ] && ok "no competing notification daemon"

hdr "Clipboard store daemon"
if pgrep -f "wl-paste --watch cliphist store" >/dev/null 2>&1; then
    ok "wl-paste --watch cliphist store is running"
else
    warn "store daemon not running — nothing is captured; restart via start.sh"
fi

hdr "Config highlights (~/.config/hyprnotch/config.json)"
CFG="$HOME/.config/hyprnotch/config.json"
if [ -f "$CFG" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CFG" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("  unreadable config:", e)
    raise SystemExit
def dig(path):
    cur = d
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur
for k in ("island.cava", "hud.enabled", "clipboard.enabled",
          "dock.blur", "island.showDate", "island.showWeather"):
    v = dig(k)
    print("  %s = %s" % (k, "(default)" if v is None else v))
PY
elif [ ! -f "$CFG" ]; then
    warn "no config file yet — everything is default"
else
    warn "python3 missing — cannot pretty-read the config"
fi

hdr "Last runtime errors (newest quickshell log)"
LOGDIR="/run/user/$(id -u)/quickshell/by-id"
NEWEST="$(ls -t "$LOGDIR"/*/log.qslog 2>/dev/null | head -1)"
if [ -n "$NEWEST" ]; then
    echo "  log: $NEWEST"
    if grep -aE "ERROR|TypeError|Cannot |not a function|Failed to load" "$NEWEST" >/dev/null 2>&1; then
        warn "errors found — last 8:"
        grep -aE "ERROR|TypeError|Cannot |not a function|Failed to load" "$NEWEST" \
            | tail -8 | sed 's/^/    /'
    else
        ok "no errors in the current log"
    fi
else
    warn "no quickshell log under $LOGDIR — is the shell running?"
fi
