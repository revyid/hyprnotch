#!/bin/sh
#  HyprNotch keybind applier — the engine behind Settings → Keybinds.
#
#  Usage: apply-keys.sh <raiz> 'MODS|KEY|ACTION' ...
#    raiz   install folder that holds shell.qml (the IPC -p target)
#    MODS   space-separated Hyprland mod names ("SUPER", "SUPER CTRL", "")
#    KEY    xkb keysym name ("SPACE", "C", "F2", "space", ...)
#    ACTION notch IPC function (launcher, controlCenter, stats, ...)
#
#  What it does, in order:
#    1. unbinds EVERY bind whose command mentions our IPC signature
#       ("shell.qml call notch") — ours only, your own chords are
#       never touched;
#    2. registers the requested set — a key still held by a non-Notch
#       bind is skipped (BUSY), never hijacked;
#    3. when a k4 Lua-fork config is detected, rewrites
#       ~/.config/hypr/config/hyprnotch.lua so the edit survives
#       `hyprctl reload`.
#
#  Output: one status line per bind, parsed by services/Keys.qml:
#    SET <mods> <key> <action>      registered
#    BUSY <mods> <key> <action>     key taken by a non-Notch bind
#    FAIL <mods> <key> <action>     hyprctl refused the bind
#    EMPTY <action>                 no chord configured for it
#    UNBOUND <mods> <key>           stale Notch bind removed
#    CANTUNBIND <mods> <key>        unbind refused — will be reported
#    LUA <path> | LUA none          Lua hook rewritten / not a Lua fork
#    NOHYPRCTL                      hyprctl missing — nothing applied

RAIZ="$1"
shift

command -v hyprctl >/dev/null 2>&1 || { echo "NOHYPRCTL"; exit 0; }

#  ── mod name <-> bitmask (Hyprland: shift=1 ctrl=4 alt=8 super=64) ──
mask_of() {
    _m=0
    for _w in $1; do
        case "$_w" in
            SHIFT|shift)                 _m=$((_m | 1)) ;;
            CTRL|ctrl|CONTROL|control)   _m=$((_m | 4)) ;;
            ALT|alt)                     _m=$((_m | 8)) ;;
            SUPER|super|WIN|win)         _m=$((_m | 64)) ;;
        esac
    done
    echo "$_m"
}
names_of() {
    _n=""
    [ $(( ($1) & 64 )) -ne 0 ] && _n="$_n SUPER"
    [ $(( ($1) & 4 ))  -ne 0 ] && _n="$_n CTRL"
    [ $(( ($1) & 8 ))  -ne 0 ] && _n="$_n ALT"
    [ $(( ($1) & 1 ))  -ne 0 ] && _n="$_n SHIFT"
    echo "${_n# }"
}
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

#  scan <sig> — reads `hyprctl -j binds` split into ONE object per line,
#  prints "modmask<TAB>lowercased-key" for lines whose text contains sig
#  ("" = all lines). One object per line means key and modmask always
#  travel together — they can never be matched across entries.
scan() {
    awk -v sig="$1" '
        {
            if (sig != "" && index($0, sig) == 0) next
            key = ""
            if (match($0, /"key"[ \t]*:[ \t]*"[^"]*"/)) {
                seg = substr($0, RSTART, RLENGTH)
                gsub(/^"key"[ \t]*:[ \t]*"/, "", seg)
                gsub(/"$/, "", seg)
                key = tolower(seg)
            }
            m = -1
            if (match($0, /"modmask"[ \t]*:[ \t]*-?[0-9]+/)) {
                mse = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", mse)
                m = mse + 0
            }
            if (key != "" && m >= 0) print m "\t" key
        }
    '
}

NOTCH_SIG="shell.qml call notch"

#  Only chords whose ACTION is in the requested set may be unbound — a
#  hand-made bind to `notch nightLight` (an action we don't manage)
#  must survive every apply.
ACTIONS="$(for req in "$@"; do printf '%s' "$req" | sed 's/.*|//'; echo; done | paste -sd, -)"

#  ── 1. unbind stale Notch binds (signature + managed action) ──────
{ hyprctl -j binds 2>/dev/null || true; } | sed 's/},{/}\n{/g' \
    | awk -v sig="$NOTCH_SIG" -v acts="$ACTIONS" '
        BEGIN {
            n = split(acts, A, ",")
            for (i = 1; i <= n; ++i) if (A[i] != "") want[A[i]] = 1
        }
        {
            if (index($0, sig) == 0) next
            rest = substr($0, index($0, sig) + length(sig))
            gsub(/[^a-zA-Z0-9_]/, " ", rest)
            split(rest, t, " ")
            if (!(t[1] in want)) next
            key = ""
            if (match($0, /"key"[ \t]*:[ \t]*"[^"]*"/)) {
                seg = substr($0, RSTART, RLENGTH)
                gsub(/^"key"[ \t]*:[ \t]*"/, "", seg)
                gsub(/"$/, "", seg)
                key = tolower(seg)
            }
            m = -1
            if (match($0, /"modmask"[ \t]*:[ \t]*-?[0-9]+/)) {
                mse = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", mse)
                m = mse + 0
            }
            if (key != "" && m >= 0) print m "\t" key
        }
    ' | while IFS="$(printf '\t')" read -r m k; do
        [ -n "$k" ] || continue
        names="$(names_of "$m")"
        if hyprctl keyword unbind "$names,$k" >/dev/null 2>&1; then
            echo "UNBOUND $names $k"
        else
            echo "CANTUNBIND $names $k"
        fi
    done

#  ── 2. register the requested set ─────────────────────────────────
#  Re-read now that our old binds are gone: whatever still holds a key
#  belongs to the user, and the bias is to LEAVE it alone.
LINES="$({ hyprctl -j binds 2>/dev/null || true; } | sed 's/},{/}\n{/g')"

for req in "$@"; do
    mods="$(printf '%s' "$req" | sed 's/|.*//')"
    rest="$(printf '%s' "$req" | sed 's/^[^|]*|//')"
    key="$(printf '%s' "$rest" | sed 's/|.*//')"
    action="$(printf '%s' "$rest" | sed 's/^[^|]*|//')"
    [ -n "$key" ] || { echo "EMPTY $action"; continue; }

    m="$(mask_of "$mods")"
    if printf '%s\n' "$LINES" | scan "" | awk -v mask="$m" -v want="$(lower "$key")" '
        { split($0, a, "\t"); if (a[1] == mask && a[2] == want) found = 1 }
        END { exit found ? 0 : 1 }
    '; then
        echo "BUSY $mods $key $action"
        continue
    fi

    notchcmd="quickshell ipc -p $RAIZ/shell.qml call notch $action"
    if hyprctl keyword bind "$mods,$key,exec,$notchcmd" >/dev/null 2>&1; then
        echo "SET $mods $key $action"
    else
        echo "FAIL $mods $key $action"
    fi
done

#  ── 3. persist for the k4 Lua fork ────────────────────────────────
LUA_CFG="$HOME/.config/hypr/hyprland.lua"
LUA_OUT="$HOME/.config/hypr/config/hyprnotch.lua"
if [ -f "$LUA_CFG" ]; then
    mkdir -p "$(dirname "$LUA_OUT")" 2>/dev/null
    if {
        printf '%s\n' \
            '-- HyprNotch keybinds — REGENERATED by Settings → Keybinds.' \
            '-- Edit chords in Settings instead of editing this file by hand;' \
            '-- every change is rewritten here so it survives hyprctl reload.' \
            '-- Revert: delete this file and the require hook in hyprland.lua.' \
            '' \
            'local raiz = "'"$(printf '%s' "$RAIZ" | sed 's/"/\\"/g')"'"' \
            'local notch = "quickshell ipc -p " .. raiz .. "/shell.qml call notch "' \
            '' \
            'hl.on("hyprland.start", function()' \
            '    hl.exec_cmd(raiz .. "/start.sh")' \
            'end)' \
            ''
        for req in "$@"; do
            mods="$(printf '%s' "$req" | sed 's/|.*//')"
            rest="$(printf '%s' "$req" | sed 's/^[^|]*|//')"
            key="$(printf '%s' "$rest" | sed 's/|.*//')"
            action="$(printf '%s' "$rest" | sed 's/^[^|]*|//')"
            [ -n "$key" ] || continue
            label="$(printf '%s' "$mods" | sed 's/ / + /g')"
            if [ -n "$label" ]; then
                printf 'hl.bind("%s + %s", hl.dsp.exec_cmd(notch .. "%s"))\n' \
                    "$label" "$key" "$action"
            else
                printf 'hl.bind("+ %s", hl.dsp.exec_cmd(notch .. "%s"))\n' \
                    "$key" "$action"
            fi
        done
    } > "$LUA_OUT" 2>/dev/null; then
        echo "LUA $LUA_OUT"
    else
        echo "LUA none"
    fi
else
    echo "LUA none"
fi
