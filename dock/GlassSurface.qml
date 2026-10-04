import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"
import "../services"

//  Liquid Glass SURFACE — hosts the refraction ShaderEffect for one
//  glass slab (the dock tray).
//
//  Pipeline (0-ss/Swift-Dock technique):
//    1. `qsb --qt6` compiles liquidglass.frag at first use (searched on
//       PATH and the usual Qt lib dirs); the result is cached as
//       liquidglass.frag.qsb next to this file, so every later launch
//       is free.  No qsb → glassState "failed" → the dock keeps its
//       frosted-glass material.  Never fatal.
//    2. A ShaderEffectSource grabs the GlassBackdrop REGION behind this
//       slab (plus a margin for refraction reach and blur).
//    3. The ShaderEffect refracts it: squircle bezel normals, Snell
//       refraction, per-channel dispersion, disk blur, specular rim,
//       grain — see liquidglass.frag.
//
//  Geometry contract: the host places this Item OVER the glass rect at
//  (-padPx, -padPx); it sizes itself glassW+2*padPx × glassH+2*padPx.

Item {
    id: glass

    //  ── Host wiring ───────────────────────────────────────────────
    property Item backdropItem: null     // GlassBackdrop (screen coords)
    property real glassX: 0              // glass rect, WINDOW coordinates
    property real glassY: 0
    property real glassW: 0
    property real glassH: 0
    property real screenH: 0             // monitor height (backdrop offset)
    property real winH: 0                // dock window height
    property real radius: 24
    property bool active: false          // master switch from the dock

    //  Look tuning (Swift-Dock defaults, dark mode).  `tint` is the
    //  dock's Translucency setting (config dock.glassOpacity) — Swift-Dock
    //  mixes it into the shader as tintMix = glassOpacity * 0.55.
    property real rimStrength: 0.45
    property real grainAmt: 0.03
    property real liquidAmt: 1.0
    property real tint: 0.42

    //  ── State machine ─────────────────────────────────────────────
    //  idle → building (qsb running) → ready | failed.  "failed" never
    //  crashes anything — the host keeps its frosted-glass fallback.
    property string glassState: "idle"
    readonly property bool ready: glassState === "ready"

    readonly property real padPx: 10
    readonly property real margin: 48    // extra backdrop around the glass

    visible: ready && active
    width: glassW + 2 * padPx
    height: glassH + 2 * padPx

    Component.onCompleted: if (active) startGlass()
    onActiveChanged: if (active) startGlass()

    readonly property string fragSrcPath:
        decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString()
                           .replace("file://", ""))
    readonly property string fragOutPath:
        decodeURIComponent(Qt.resolvedUrl(".").toString().replace("file://", ""))
        + "liquidglass.frag.qsb"
    readonly property url fragOutUrl: "file://" + fragOutPath

    function startGlass() {
        if (!active || glassState === "ready" || glassState === "building")
            return
        glassState = "building"
        qsbProc.running = true
    }

    Process {
        id: qsbProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb "
            + "/usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then "
            + "\"$q\" --qt6 -o \"$2\" \"$1\" && exit 0; fi; done; "
            + "[ -f \"$1.qsb\" ] && cp \"$1.qsb\" \"$2\" && exit 0; "
            + "exit 1",
            "sh", glass.fragSrcPath, glass.fragOutPath]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                console.warn("glass: qsb:", text.trim())
        }
        onExited: function (code) {
            glass.glassState = code === 0 ? "ready" : "failed"
            if (code !== 0)
                console.warn("glass: qsb unavailable — frosted-glass fallback")
        }
    }

    //  ── The backdrop region behind this slab ──────────────────────
    ShaderEffectSource {
        id: bsrc
        visible: false
        hideSource: true
        live: glass.ready && glass.active
        sourceItem: glass.backdropItem
        sourceRect: Qt.rect(
            glass.glassX - glass.padPx - glass.margin,
            glass.glassY + (glass.screenH - glass.winH)
                - glass.padPx - glass.margin,
            glass.glassW + 2 * (glass.padPx + glass.margin),
            glass.glassH + 2 * (glass.padPx + glass.margin))
    }

    //  ── The glass itself ──────────────────────────────────────────
    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: glass.ready
        fragmentShader: glass.ready ? glass.fragOutUrl : ""
        onStatusChanged: {
            if (status === ShaderEffect.Error) {
                glass.glassState = "failed"
                console.warn("glass: shader error —", log)
            }
        }

        property variant src: bsrc
        property real pad: glass.padPx
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d glassSize: Qt.vector2d(glass.glassW, glass.glassH)
        property vector2d srcSize: Qt.vector2d(bsrc.sourceRect.width,
                                               bsrc.sourceRect.height)
        property vector2d srcOffset: Qt.vector2d(glass.margin, glass.margin)
        property real radius: glass.radius
        property real bezel: Math.min(glass.glassH * 0.36, 26)
        property real thickness: 30 * glass.liquidAmt
        property real dispersion: 0.06 * glass.liquidAmt
        property real magnify: 0.08 * glass.liquidAmt
        property real rim: glass.rimStrength
        property real grain: glass.grainAmt
        property real blurPx: 5
        property real tintMix: glass.tint * 0.55
        property real saturation: 1.25
        property real dark: 1
        property real debug: 0
    }
}
