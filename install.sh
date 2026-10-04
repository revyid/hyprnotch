#!/bin/sh
#  HyprNotch installer — checks dependencies and copies the shell into
#  ~/.config/quickshell/hyprnotch. 100% English on purpose.

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
printf '  ██║  ██║   ██║   ██║     ██║  ██║\n'
printf '  ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝\n'
printf '   macOS-style island shell for Hyprland\n\n'

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/quickshell/hyprnotch"

info "Checking dependencies..."

check() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1"
    else
        warn "$1 not found — install it: $2"
        MISSING=1
    fi
}

MISSING=0
check quickshell "your distro package (Arch: paru -S quickshell-git) — REQUIRED"
check hyprctl     "Hyprland — REQUIRED"
check nmcli       "networkmanager"
check brightnessctl "brightnessctl (brightness slider)"
check playerctl   "playerctl (optional, media via MPRIS is built-in)"
check podman      "podman (optional, container manager)"

if [ "$MISSING" -ne 0 ]; then
    printf '\n'
    warn "Some optional tools are missing — HyprNotch will degrade gracefully."
    if ! command -v quickshell >/dev/null 2>&1; then
        fail "quickshell is REQUIRED. Install it first, then re-run ./install.sh"
    fi
fi

info "Installing to $DEST"
mkdir -p "$DEST"
COPY_FAIL=0
for item in core services island dock panels shell.qml README.md sample-hyprland.conf VERSION start.sh; do
    [ -e "$HERE/$item" ] || continue
    rm -rf "$DEST/$item"
    if ! cp -r "$HERE/$item" "$DEST/$item"; then
        warn "could not copy '$item'"
        COPY_FAIL=1
    fi
done
chmod +x "$DEST/start.sh" 2>/dev/null
[ "$COPY_FAIL" -eq 0 ] || fail "Installation incomplete — fix permissions and re-run ./install.sh"

ok "Files copied (build $(cat "$DEST/VERSION" 2>/dev/null || echo v1))."

printf '\n'
info "Add these binds to your hyprland.conf (see sample-hyprland.conf):"
printf '    exec-once = ~/.config/quickshell/hyprnotch/start.sh\n'
printf '    bind = SUPER, C, exec, quickshell -p ~/.config/quickshell/hyprnotch/shell.qml call notch controlCenter\n'
printf '    bind = SUPER, K, exec, quickshell -p ~/.config/quickshell/hyprnotch/shell.qml call notch calendar\n'
printf '    bind = SUPER, D, exec, quickshell -p ~/.config/quickshell/hyprnotch/shell.qml call notch launcher\n'
printf '\n'
info "Nerd Font required for icons: install a Nerd Font (e.g. ttf-meslo-nerd)."
ok "Done — run 'start.sh' or log into Hyprland."
printf '\n'
