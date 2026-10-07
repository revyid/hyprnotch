pragma Singleton

//  HyprNotch design tokens — macOS Dynamic Island look.
//  Pure data: does not depend on anything, so everything else can
//  import Theme safely (it is the root of the import graph).

import QtQuick
import Quickshell

Singleton {
    id: theme

    //  Fonts. UI font falls back gracefully; icons REQUIRE a Nerd Font
    //  (MesloLGS NF). See README for the dependency line.
    readonly property string uiFont: "Adwaita Sans"
    readonly property string iconFont: "MesloLGS Nerd Font Mono"

    //  ── Palette (macOS dark, Apple HIG system colors) ────────────
    readonly property color islandBg: "#000000"
    readonly property color ink: "#ffffff"
    readonly property color muted: "#8e8e93"
    readonly property color dim: "#48484a"
    readonly property color surface: "#1c1c1e"
    readonly property color surfaceHi: "#2c2c2e"
    readonly property color track: "#3a3a3c"
    //  HIG system palette (dark variant)
    readonly property color blue: "#0a84ff"
    readonly property color green: "#30d158"
    readonly property color red: "#ff453a"
    readonly property color yellow: "#ffd60a"
    readonly property color orange: "#ff9f0a"
    readonly property color teal: "#64d2ff"
    readonly property color purple: "#bf5af2"
    readonly property color separator: "#20ffffff"
    readonly property color backdrop: "#80000000"

    //  Accent is user-configurable (Config.data.general.accent) but QML
    //  bindings need a plain property here; Config writes into it on load
    //  and on every change, so the whole UI re-tints live.
    property color accent: "#0a84ff"

    //  ── Geometry (compact by design) ──────────────────────────────
    readonly property int pillHeight: 36
    readonly property int radiusPill: 999
    //  k4 island DNA: inverted-corner wing + body rounding (expanded)
    readonly property int wing: 16
    readonly property int islandRadius: 32
    readonly property int baseHeight: 34
    readonly property int radiusCard: 14
    readonly property int radiusTile: 12
    readonly property int radiusSmall: 8
    readonly property int marginTight: 8
    readonly property int marginBase: 12
    readonly property int fontSizeSmall: 10
    readonly property int fontSizeBase: 12
    readonly property int fontSizeTitle: 14

    //  ── Motion (k4 DNA + HIG feel) ────────────────────────────────
    readonly property int animPress: 120
    readonly property int animFast: 140
    readonly property int animBase: 220
    readonly property int animSlow: 380
    readonly property int animSpring: 440

    //  The k4 island spring, verbatim: OutBack with tuned overshoot.
    //  Width springs harder than height — that asymmetry is what makes
    //  the island read as elastic rather than as a bounce.
    readonly property int springWidth: 440
    readonly property int springHeight: 400
    readonly property real springWidthOvershoot: 0.42
    readonly property real springHeightOvershoot: 0.32

    //  Standard easing for non-island motion (dock tuck, card fades).
    readonly property int easingType: Easing.OutCubic

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
}
