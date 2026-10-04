#!/bin/sh
#  HyprNotch installer — checks dependencies (REQUIRED vs OPTIONAL),
#  copies the shell into ~/.config/quickshell/hyprnotch, and wires the
#  keybinds. Three config shapes are detected, k4-style:
#    1. Lua fork   (~/.config/hypr/hyprland.lua)   -> config/hyprnotch.lua + require hook
#    2. Classic    (~/.config/hypr/hyprland.conf)  -> ready-made binds appended
#    3. Neither                                    -> start.sh registers binds at runtime
#  100% English on purpose.

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()  { printf "${CYAN}==>${NC} %s\n" "$1"; }
ok()    { printf "${GREEN} ok${NC}  %s\n" "$1"; }
warn()  { printf "${YELLOW} !!${NC}  %s\n" "$1"; }
fail()  { printf "${RED}fail${NC} %s\n" "$1"; exit 1; }

printf '\n'
printf '  ██╗  ██╗██╗   ██╗██████╗ ██████╗ \n'
printf '  ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗\n'
printf '  ███████║ ╚████╔╝ ██████╔╝██████╔╝\n'
printf '  ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗\n'
printf '  ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝\n'
printf '   macOS-style island shell for Hyprland\n\n'

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/quickshell/hyprnotch"

#  ── 1. REQUIRED dependencies ──────────────────────────────────────
info "Checking required dependencies..."
MISSING=0
need() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1"
    else
        warn "$1 missing — $2"
        MISSING=1
    fi
}
need quickshell "REQUIRED — the shell itself (Arch: paru -S quickshell-git)"
need hyprctl    "REQUIRED — Hyprland (this shell is a Hyprland layer)"

if [ "$MISSING" -ne 0 ]; then
    fail "Install the required tools first, then re-run ./install.sh"
fi

#  ── 2. OPTIONAL integrations — everything is a choice ────────────
#  HyprNotch degrades gracefully: decline anything you don't want.
have_pacman=0
command -v pacman >/dev/null 2>&1 && have_pacman=1

opt() {
    #  opt <binary[|alt]> <pkg> <why> — any of the binaries counts as present
    for b in $(printf '%s' "$1" | tr '|' ' '); do
        if command -v "$b" >/dev/null 2>&1; then
            ok "$b present"
            return
        fi
    done
    printf "    install %s? [y/N] " "$2"
    read -r ans || ans=""
    case "$ans" in
        y|Y)
            if [ "$have_pacman" -eq 1 ]; then
                if sudo pacman -S --needed "$2"; then
                    ok "$2 installed"
                else
                    warn "could not install $2 — HyprNotch degrades gracefully"
                fi
            else
                warn "no pacman (not Arch) — install $2 manually. Why: $3"
            fi
            ;;
        *)
            warn "skipping $2 — HyprNotch degrades gracefully"
            ;;
    esac
}

printf '\n'
info "Optional integrations (decline anything you don't want):"
opt nmcli             networkmanager             "Wi-Fi manager tiles"
opt brightnessctl     brightnessctl              "brightness HUD + slider"
opt "awww|swww"       swww                       "wallpaper picker transitions (awww fork or swww)"
opt qsb               qt6-shadertools            "dock Liquid Glass shader (frosted-glass fallback without it)"
opt playerctl         playerctl                  "media helper (MPRIS is built-in anyway)"
opt powerprofilesctl  power-profiles-daemon      "battery Energy Mode"
opt podman            podman                     "container manager panel"

if ! fc-list 2>/dev/null | grep -qi "nerd"; then
    printf "    install a Nerd Font (icons require it)? [y/N] "
    read -r ans || ans=""
    case "$ans" in
        y|Y)
            if [ "$have_pacman" -eq 1 ]; then
                sudo pacman -S --needed ttf-meslo-nerd || warn "font install failed — icons will look wrong until you add a Nerd Font"
            else
                warn "install a Nerd Font manually (e.g. MesloLGS NF)"
            fi
            ;;
        *) warn "skipping font — status icons need a Nerd Font to render" ;;
    esac
fi

#  ── 3. Copy the shell ─────────────────────────────────────────────
info "Installing to $DEST"
mkdir -p "$DEST"
COPY_FAIL=0
for item in core services island dock panels plugins scripts shell.qml \
            README.md sample-hyprland.conf hyprnotch.lua LICENSE VERSION start.sh; do
    [ -e "$HERE/$item" ] || continue
    rm -rf "$DEST/$item"
    if ! cp -r "$HERE/$item" "$DEST/$item"; then
        warn "could not copy '$item'"
        COPY_FAIL=1
    fi
done
chmod +x "$DEST/start.sh" "$DEST/scripts/test.sh" 2>/dev/null
[ "$COPY_FAIL" -eq 0 ] || fail "Installation incomplete — fix permissions and re-run ./install.sh"

ok "Files copied (build $(cat "$DEST/VERSION" 2>/dev/null || echo v1))."

#  ── 4. Keybinds — detect the config shape, k4-style ───────────────
HYPR_DIR="$HOME/.config/hypr"
LUA_TARGET="$HYPR_DIR/config/hyprnotch.lua"
LUA_HOOK='require("config.hyprnotch")'

printf '\n'
printf "    wire up the island keybinds (Super+C, Super+T, ...)? [Y/n] "
read -r ans || ans=""
case "$ans" in
    n|N) info "Skipped. sample-hyprland.conf has every bind; start.sh also registers them at runtime." ;;
    *)
        if [ -f "$HYPR_DIR/hyprland.lua" ]; then
            #  ── Lua fork (k4 / hyprlang-lua): our own Lua module + hook ──
            mkdir -p "$(dirname "$LUA_TARGET")"
            if sed "s|@RAIZ@|$DEST|g" "$HERE/hyprnotch.lua" > "$LUA_TARGET"; then
                ok "Written $LUA_TARGET (Lua fork detected)."
                if grep -qF "$LUA_HOOK" "$HYPR_DIR/hyprland.lua" 2>/dev/null; then
                    ok "Hook already present in hyprland.lua."
                else
                    printf '\n-- HyprNotch: keybinds and bar startup\n%s\n' "$LUA_HOOK" >> "$HYPR_DIR/hyprland.lua"
                    ok "Hooked into hyprland.lua (require at the end — your binds win above it)."
                fi
                warn "Reload Hyprland to pick it up. Revert = delete the file + the hook line."
            else
                warn "could not write $LUA_TARGET — see hyprnotch.lua in the install folder."
            fi
        elif [ -f "$HYPR_DIR/hyprland.conf" ] || [ -f "$HOME/.config/hyprland/hyprland.conf" ]; then
            HL="$HOME/.config/hypr/hyprland.conf"
            [ -f "$HL" ] || HL="$HOME/.config/hyprland/hyprland.conf"
            if grep -qF "HyprNotch keybinds" "$HL" 2>/dev/null; then
                ok "Binds already appended to $HL — nothing to do."
            else
                printf '\n# ── HyprNotch keybinds (added by install.sh) ──\n' >> "$HL"
                sed "s|@RAIZ@|$DEST|g" "$HERE/sample-hyprland.conf" >> "$HL"
                ok "Keybinds appended to $HL — reload Hyprland to activate."
            fi
        else
            warn "No hyprland.conf / hyprland.lua found in $HYPR_DIR."
            info "No problem: start.sh registers the binds at RUNTIME via"
            info "  'hyprctl keyword bind ...' every launch — keys work with"
            info "  zero config edits, until a manual 'hyprctl reload'."
            info "To persist them, copy sample-hyprland.conf (classic) or"
            info "hyprnotch.lua (k4 Lua fork) manually."
        fi
        ;;
esac

printf '\n'
ok "Done — run 'start.sh' or log into Hyprland."
printf '    Island shortcuts: Super+Space launcher · Super+C control center · Super+T stats\n'
printf '    ALL chords are editable live in Settings → Keybinds (Settings window: Super+S).\n'
printf '    About This Device: Super+I, or Control Center → System\n'
printf '    Wallpaper picker:  Super+G, or Control Center → System → Wallpaper\n'
printf '    Plugins menu: Super+O, or Control Center → Plugins → Manage\n'
printf '\n'
