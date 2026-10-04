#!/bin/sh
#  HyprNotch installer — checks dependencies (REQUIRED vs OPTIONAL),
#  copies the shell into ~/.config/quickshell/hyprnotch, and can append
#  the ready-made keybinds to your hyprland.conf. 100% English on purpose.

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
    #  opt <binary> <pkg> <why>
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1 present"
        return
    fi
    printf "    install %s? [y/N] " "$1"
    read -r ans || ans=""
    case "$ans" in
        y|Y)
            if [ "$have_pacman" -eq 1 ]; then
                if sudo pacman -S --needed "$2"; then
                    ok "$1 installed"
                else
                    warn "could not install $1 — HyprNotch degrades gracefully"
                fi
            else
                warn "no pacman (not Arch) — install $1 manually. Why: $3"
            fi
            ;;
        *)
            warn "skipping $1 — HyprNotch degrades gracefully"
            ;;
    esac
}

printf '\n'
info "Optional integrations (decline anything you don't want):"
opt nmcli             networkmanager             "Wi-Fi manager tiles"
opt brightnessctl     brightnessctl              "brightness HUD + slider"
opt swww              swww                       "wallpaper picker transitions"
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
            README.md sample-hyprland.conf LICENSE VERSION start.sh; do
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

#  ── 4. Keybinds — optional auto-append with the $notch variable ───
printf '\n'
printf "    append the ready-made keybinds (the \$notch variable) to your hyprland.conf? [y/N] "
read -r ans || ans=""
case "$ans" in
    y|Y)
        HL="$HOME/.config/hyprland/hyprland.conf"
        [ -f "$HL" ] || HL="$HOME/.config/hypr/hyprland.conf"
        if [ -f "$HL" ]; then
            printf '\n# ── HyprNotch keybinds (added by install.sh) ──\n' >> "$HL"
            sed "s|@RAIZ@|$DEST|g" "$HERE/sample-hyprland.conf" >> "$HL"
            ok "Keybinds appended to $HL — review them and reload Hyprland."
            warn "Re-running install.sh appends them again — dedupe if needed."
        else
            warn "hyprland.conf not found — copy sample-hyprland.conf manually."
        fi
        ;;
    *) info "Skipped. See sample-hyprland.conf for the \$notch variable and all binds." ;;
esac

printf '\n'
ok "Done — run 'start.sh' or log into Hyprland."
printf '    Island shortcuts: Super = launcher · Super+C control center · Super+T stats\n'
printf '    Plugins menu: Super+O, or Control Center → Plugins → Manage\n'
printf '\n'
