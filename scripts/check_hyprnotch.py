#!/usr/bin/env python3
"""HyprNotch QML sanity checks v5 (no Qt toolchain needed).

v2: brace balance, local type resolution, import presence.
v3 — property-existence validation on local components.
v4 — PanelWindow root whitelist (quickshell windows lack e.g. opacity)
  + WlrLayershell nested-enum ban (use WlrKeyboardFocus standalone type).
v5 — read-only property class:
  · assigning to a readonly custom property of a local component
  · `Behavior on X` where X is readonly or not a property of its owner
    (Catches: Invalid property assignment: "size" is a read-only property)
  5. Every property assigned on a LOCAL component instance must be declared
     by that component (or its local base chain) or exist on its whitelisted
     base type.  (Catches: 'Cannot assign to non-existent property "glyph"')
  6. Every `onX:` handler on a local component must match a declared signal,
     property, or property+'Changed'.
  7. Singleton member references (Theme.x, Audio.y()) must be declared.
  8. id/property name collisions + duplicate ids inside one file.
v6 — duplicate method names per object (Catches: 'Duplicate method
  name' — e.g. switchTo() defined twice after a merge) and duplicate
  property declarations per object.
v7 — <Prop>Changed handlers on module-type objects: the target must be
  a real property of that object's type (or, at the file root, a prop
  declared in the file).  (Catches: 'Cannot assign to non-existent
  property "onValuesChanged"' — handler attached to a Canvas child for
  a property that lives on the file root.)
v8 — arrow-function bodies must be an expression or a {block}:
  `=> if (...)` is invalid JS.  (Catches: 'Unexpected token `if' /
  'Expected token `,`' — onPositionChanged: (m) => if (pressed) f())
v9 — duplicate signal handlers on one object: the engine rejects the
  second assignment and the whole file fails to load.
v10 — object declaration through an id (`settingsWindow.AboutGroup {`):
  ids are NOT types or namespaces — inline/local components must be
  referenced by bare name.  (Catches: 'settingsWindow.AboutGroup -
  settingsWindow is neither a type nor a namespace')
v11 — infinite-loop probe processes must be started: a Process whose
  shell command ends in `while :; do ... done` only produces data if it
  is running.  The file must set `running: true` on the Process or
  assign `<id>.running = true` somewhere.  (Catches: 'system stats are
  stuck at 0' — SysMon probes declared but never started.)
v12 — local type names colliding with Qt built-in attached/element
  types: a singleton or inline component named Keys/Layout/Settings/
  Timer/... shadows (or ambiguates) the QtQuick type in every file
  importing its module — attached handlers like Keys.onPressed break.
  (Catches: naming a service Keys.qml when the capture editor needs
  QtQuick's attached Keys type; renamed to Hotkeys.)
v13 — an Image whose source binds modelData (arbitrary file paths:
  wallpaper thumbnails, app icons from a model) MUST declare
  sourceSize. Without it Qt decodes every file at FULL resolution —
  a 4K wallpaper costs ~33 MB per thumbnail, and the wallpaper picker
  alone OOM-killed the whole shell seconds after opening it.
  (Catches: "Killed" in ./start.sh logs — systemd-oomd terminating
  quickshell.)
v14 — ScrollIndicator/ScrollBar live in QtQuick.Controls, NOT QtQuick.
  The v13 import map claimed ScrollIndicator -> "QtQuick", so a file
  using `ScrollIndicator.vertical: ScrollIndicator {}` with only
  `import QtQuick` passed validation and then failed at load time with
  "ScrollIndicator is not a type" — which cascades: LauncherCard ->
  IslandWindow -> "Failed to load configuration".  Map corrected, and
  the whole QtQuick.Controls family is now held to the same rule.
  (Catches: @island/LauncherCard.qml[315:13]: ScrollIndicator is not
  a type — launcher/wallpaper picker dead on r16.)
v15 — Keys attached CONVENIENCE handlers are not portable across
  Qt/Quickshell builds. The user's build rejected
  Keys.onPageDownPressed with 'Cannot assign to non-existent property'
  while resolving its PageUp twin one line earlier — doc-vs-build
  divergence, load aborted, island dead (r17 round). Only the
  universal trio exists everywhere: onPressed, onReleased,
  onShortcutOverride. Everything else must go through Keys.onPressed
  with explicit event.key checks (the IslandWindow pattern).
  (Catches: LauncherCard.qml[288:22] onPageDownPressed and any future
  on<Nav>Pressed / on<Fk>Pressed convenience handler.)
v16 — Liquid Glass round: ScreencopyView (Quickshell.Wayland),
  ShaderEffect / ShaderEffectSource / ListModel (QtQuick) added to the
  module map so the new dock glass components are import-checked like
  everything else.
v17 — Swift-Dock dock port: ToplevelManager (Quickshell.Wayland) and
  Shortcut (QtQuick) added to the module map — the dock's windowsFor()
  iterates ToplevelManager.toplevels and an unimported reference would
  fail at load time exactly like the ScrollIndicator class of r16.
v18 — hyprland-dock (nick-friedrich) port: the dock now uses surfaces
  hyprnotch never touched before, verified against the Quickshell source
  tree (popupwindow.hpp, popupanchor.hpp, widgets/IconImage.qml,
  desktopentry.hpp, wayland/toplevel/qml.hpp) and now import-enforced:
  IconImage (Quickshell.Widgets), DragHandler (QtQuick), PopupAdjustment /
  Edges / ExclusionMode (Quickshell), WlrLayer (Quickshell.Wayland),
  DesktopEntries + QsWindow (Quickshell).  PopupWindow's surface map
  gains grabFocus (popupwindow.hpp:87) and IconImage / DragHandler get
  whitelists.  (Catches: unimported IconImage — "unresolved type" or a
  load-time 'IconImage is not a type' cascade like r16.)

v19 — runtime-warning round from the r21 start log (the config finally
  loaded, but the console was noisy and two features silently
  degraded):
  a) positioner anchors: a DIRECT child of Row may not use anchors.
     left/right/horizontalCenter/fill/centerIn and a direct child of
     Column may not use anchors.top/bottom/verticalCenter/fill/
     centerIn — Qt warns "Cannot specify ... for items inside Row.
     Row will not function." and silently keeps the default layout
     (the ControlCenterCard weather head warned 5x per relayout;
     fixed by making it an Item, which has no anchor restrictions).
  b) GLSL shaders (*.frag / *.vert) must declare `#version 440` as the
     first non-comment line: qsb compiles Vulkan-style GLSL and
     transpiles to ES 310 / SPIR-V itself. Without the line qsb parses
     the source as GLSL ES 1.00 and rejects it ("ES shaders for
     SPIR-V require version 310 or higher" + "'float': type requires
     declaration of default precision qualifier") — liquidglass.frag
     shipped exactly like that, so the Liquid Glass dock silently ran
     on its frosted-glass fallback. Legacy ES-1.00 tokens (varying /
     attribute / texture2D / gl_FragColor / gl_FragData) are banned
     for the same reason.
  c) a ShaderEffect wired to a .frag/.vert must declare its
     non-sampler properties in EXACTLY the order of the shader's
     std140 `uniform buf` members (after qt_Matrix / qt_Opacity):
     both sides define one shared buffer layout, so order drift turns
     the effect into garbage instead of an error. Samplers
     (variant/var) are matched by name and excluded.
  d) Hyprland.dispatch is only allowed in services/Hypr.qml — Lua
     Hyprland (0.56+ hl.* API, incl. the user's k4 build) evaluates
     dispatch requests as `return hl.dispatch(<raw text>)`, so every
     call must go through the strategy-wrapped helpers
     (Hypr.dispatch / Hypr.switchTo) that emit hl.dsp.* expressions
     there and classic text on pre-Lua builds.
  (Catches: weather Row anchors 5x-warning; liquidglass.frag missing
  #version; GlassSurface property-order drift; stray raw dispatches.)
"""
import os, re, sys

#  Qt types a local QML type must never be named after — attached types
#  first (shadowing them silently breaks their attached handlers), then
#  high-traffic elements every file instantiates.
QT_BUILTIN_NAMES = {
    "Keys", "Layout", "Settings", "State", "AnchorChanges",
    "ParentChange", "PropertyChanges", "SystemPalette", "StandardPaths",
    "Font",
    "Timer", "Process", "Image", "Text", "MouseArea", "Item",
    "Rectangle", "Column", "Row", "Flickable", "Loader", "Repeater",
    "Canvas", "Gradient",
}

ROOT = (sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
#  v19: force an absolute root — os.walk keys and os.path.normpath results
#  (relative-import resolution) must agree, or component_file() KeyErrors
#  when invoked as `python3 scripts/check_hyprnotch.py .` from the repo.
ROOT = os.path.abspath(ROOT)

REQUIRED_MODULE = {
    "Singleton": "Quickshell", "PanelWindow": "Quickshell",
    "PopupWindow": "Quickshell", "ShellRoot": "Quickshell",
    "Variants": "Quickshell", "Screen": "Quickshell",
    "Process": "Quickshell.Io", "FileView": "Quickshell.Io",
    "FileWatcher": "Quickshell.Io", "Socket": "Quickshell.Io",
    "SplitParser": "Quickshell.Io", "StdioCollector": "Quickshell.Io",
    "IpcHandler": "Quickshell.Io", "JsonAdapter": "Quickshell.Io",
    "Hyprland": "Quickshell.Hyprland",
    "WlrLayershell": "Quickshell.Wayland",
    "WlrKeyboardFocus": "Quickshell.Wayland",
    "Networking": "Quickshell.Networking",
    "DeviceType": "Quickshell.Networking",
    "WifiSecurityType": "Quickshell.Networking",
    "Bluetooth": "Quickshell.Bluetooth",
    "PwObjectTracker": "Quickshell.Services.Pipewire",
    "Pipewire": "Quickshell.Services.Pipewire",
    "Mpris": "Quickshell.Services.Mpris",
    "NotificationServer": "Quickshell.Services.Notifications",
    "GridLayout": "QtQuick.Layouts", "RowLayout": "QtQuick.Layouts",
    "ColumnLayout": "QtQuick.Layouts", "TextField": "QtQuick.Controls",
    "TextArea": "QtQuick.Controls", "ScrollBar": "QtQuick.Controls",
    "HoverHandler": "QtQuick", "TapHandler": "QtQuick",
    "ScrollIndicator": "QtQuick.Controls",
    "RotationAnimation": "QtQuick", "Translate": "QtQuick",
    "Region": "Quickshell",
    "Button": "QtQuick.Controls", "ComboBox": "QtQuick.Controls",
    "CheckBox": "QtQuick.Controls", "Slider": "QtQuick.Controls",
    "ProgressBar": "QtQuick.Controls",
    "Shape": "QtQuick.Shapes", "ShapePath": "QtQuick.Shapes",
    "PathArc": "QtQuick.Shapes", "PathLine": "QtQuick.Shapes",
    "Binding": "QtQuick", "Canvas": "QtQuick",
    "ShaderEffect": "QtQuick", "ShaderEffectSource": "QtQuick",
    "ListModel": "QtQuick",
    "ScreencopyView": "Quickshell.Wayland",
    "ToplevelManager": "Quickshell.Wayland",
    "MultiEffect": "QtQuick.Effects",
    "Shortcut": "QtQuick",
    "IconImage": "Quickshell.Widgets",
    "DragHandler": "QtQuick",
    "PopupAdjustment": "Quickshell",
    "Edges": "Quickshell",
    "ExclusionMode": "Quickshell",
    "WlrLayer": "Quickshell.Wayland",
    "DesktopEntries": "Quickshell",
    "QsWindow": "Quickshell",
}

#  Properties that exist on Quickshell's PanelWindow (proven: IslandWindow
#  compiles on the user's Quickshell; linux-notch ran for months there —
#  k4's shell.qml uses aboveWindows/focusable/mask on the same build).
PANEL_PROVEN = {
    "anchors", "color", "exclusionMode", "exclusiveZone", "mask",
    "screen", "visible", "width", "height",
    "implicitWidth", "implicitHeight",
    "aboveWindows", "focusable",
}

QT_BASE = {
    "Rectangle", "Item", "Text", "MouseArea", "Column", "Row", "Grid",
    "Repeater", "Loader", "Component", "Timer", "Image", "TextInput",
    "TextEdit", "Flickable", "ListView", "Window", "Connections",
    "NumberAnimation", "ColorAnimation", "Behavior", "SequentialAnimation",
    "ParallelAnimation", "PauseAnimation", "PropertyAnimation",
    "Qt", "Font", "Easing", "Canvas",
}

# ---- whitelisted inherited properties per base type -----------------------
I = set("x y width height visible enabled opacity rotation scale z clip focus "
        "activeFocus state states transitions transform transformOrigin data "
        "resources children parent anchors implicitWidth implicitHeight layer "
        "smooth antialiasing baselineOffset containmentMask palette".split())
R = I | {"color", "radius", "border", "gradient"}
BASE_PROPS = {
    "Item": I, "Rectangle": R,
    "Text": R | {"text", "font", "style", "styleColor", "elide", "wrapMode",
                 "horizontalAlignment", "verticalAlignment", "lineHeight",
                 "maximumLineCount", "minimumPixelSize", "fontSizeMode",
                 "renderType", "textFormat", "linkColor"},
    "MouseArea": I | {"hoverEnabled", "cursorShape", "acceptedButtons", "drag",
                      "pressed", "containsMouse", "mouseX", "mouseY",
                      "propagateComposedEvents", "preventStealing",
                      "scrollGestureEnabled", "hovered", "containsPress",
                      "position"},  # positionChanged signal (no property),
    "Row": I | {"spacing", "add", "move", "populate", "layoutDirection",
                "padding", "leftPadding", "rightPadding", "topPadding",
                "bottomPadding"},
    "Column": I | {"spacing", "add", "move", "populate", "padding",
                   "leftPadding", "rightPadding", "topPadding", "bottomPadding"},
    "Grid": I | {"rows", "columns", "rowSpacing", "columnSpacing", "flow",
                 "horizontalItemAlignment", "verticalItemAlignment", "spacing",
                 "padding", "populate", "add", "move"},
    "Repeater": I | {"model", "delegate", "count"},
    "Loader": I | {"source", "sourceComponent", "active", "asynchronous",
                   "item", "status", "progress"},
    "Timer": I | {"interval", "running", "repeat", "triggeredOnStart"},
    "Connections": I | {"target", "ignoreUnknownSignals", "enabled", "function"},
    "Image": I | {"source", "sourceSize", "fillMode", "asynchronous", "cache",
                  "mipmap", "status", "progress", "autoTransform",
                  "paintedWidth", "paintedHeight"},
    "TextInput": I | {"text", "color", "font", "echoMode", "passwordCharacter",
                      "readOnly", "selectedTextColor", "selectionColor",
                      "cursorPosition", "cursorVisible", "selectByMouse",
                      "maximumLength", "validator", "inputMethodHints",
                      "verticalAlignment", "horizontalAlignment",
                      "autoScroll", "persistentSelection"},
    "TextEdit": I | {"text", "color", "font", "readOnly", "wrapMode",
                     "textFormat", "persistentSelection", "overwriteMode",
                     "selectByMouse", "cursorPosition", "cursorVisible",
                     "selectionColor", "selectedTextColor",
                     "verticalAlignment", "horizontalAlignment", "baseUrl"},
    "TextField": I | {"text", "placeholderText", "color", "font", "echoMode",
                      "readOnly", "selectByMouse", "placeholderTextColor",
                      "background", "contentItem", "cursorPosition",
                      "verticalAlignment", "horizontalAlignment",
                      "inputMethodHints", "validator", "maximumLength",
                      "selectionColor", "selectedTextColor", "focus",
                      "hovered", "pressed", "passwordCharacter", "wrapMode"},
    "TextArea": I | {"text", "placeholderText", "color", "font", "readOnly",
                     "wrapMode", "textFormat", "selectByMouse", "background",
                     "contentItem", "placeholderTextColor", "persistentSelection",
                     "cursorPosition", "verticalAlignment"},
    "CheckBox": I | {"text", "checked", "tristate", "indicator", "background",
                     "contentItem", "font", "spacing", "hoverEnabled", "down",
                     "pressed", "display", "icon", "focus"},
    "Button": I | {"text", "icon", "flat", "highlighted", "down", "checked",
                   "background", "contentItem", "font", "display", "padding",
                   "hoverEnabled", "spacing", "focus"},
    "Slider": I | {"from", "to", "value", "stepSize", "orientation", "live",
                   "snapMode", "pressed", "position", "visualPosition",
                   "wheelEnabled", "background", "handle", "padding",
                   "hoverEnabled"},
    "ProgressBar": I | {"from", "to", "value", "indeterminate"},
    "ComboBox": I | {"model", "delegate", "displayText", "currentIndex",
                     "editText", "editable", "popup", "indicator",
                     "background", "contentItem", "textRole", "valueRole",
                     "count", "font", "pressed", "down", "flat", "spacing"},
    "Flickable": I | {"contentX", "contentY", "contentWidth", "contentHeight",
                      "flickDeceleration", "maximumFlickVelocity",
                      "boundsBehavior", "interactive", "flickableDirection",
                      "originX", "originY", "pressDelay", "pixelAligned"},
    "ListView": I | {"orientation", "spacing", "delegate", "model",
                     "currentIndex", "count", "highlight", "highlightItem",
                     "highlightRangeMode", "highlightMoveDuration",
                     "highlightResizeDuration", "preferredHighlightBegin",
                     "preferredHighlightEnd", "snapMode", "section", "header",
                     "headerItem", "footer", "footerItem", "cacheBuffer",
                     "reuseItems", "keyNavigationEnabled", "contentX",
                     "contentY", "contentWidth", "contentHeight",
                     "flickDeceleration", "maximumFlickVelocity",
                     "boundsBehavior", "interactive", "flickableDirection",
                     "originX", "originY", "pressDelay", "pixelAligned"},
    "NumberAnimation": I | {"duration", "target", "property", "properties",
                            "from", "to", "easing", "loops", "running",
                            "alwaysRunToEnd"},
    "ColorAnimation": I | {"duration", "target", "property", "properties",
                           "from", "to", "easing", "loops", "running",
                           "alwaysRunToEnd"},
    "SequentialAnimation": I | {"running", "loops", "alwaysRunToEnd"},
    "Behavior": I | {"animation", "enabled"},
    "HoverHandler": I | {"hovered", "hoverEnabled", "acceptedButtons",
                         "cursorShape", "blocking", "enabled", "point"},
    "TapHandler": I | {"tapped", "pressed", "gesturePolicy", "acceptedButtons",
                       "exclusive", "enabled"},
    "RotationAnimation": I | {"from", "to", "duration", "running", "loops",
                              "direction", "easing", "alwaysRunToEnd",
                              "target", "property"},
    "Translate": I | {"x", "y"},
    "Region": I | {"item", "intersection"},
    "Transition": I | {"from", "to", "reversible", "running"},
    "State": I | {"name", "when", "changes"},
    "Shape": I | {"asynchronous", "containmentMode", "data", "renderType"},
    "ShapePath": I | {"fillColor", "strokeColor", "strokeWidth", "fillTransform",
                      "startX", "startY", "dashPattern", "capStyle", "joinStyle"},
    "PathArc": I | {"x", "y", "radiusX", "radiusY", "useLargeArc",
                    "direction", "relativeX", "relativeY"},
    "PathLine": I | {"x", "y", "relativeX", "relativeY"},
    "Canvas": I | {"context", "contextType", "available", "renderTarget",
                   "renderStrategy", "getContext", "requestPaint", "cancelRequestPaint",
                   "save", "restore", "scale", "rotate", "translate", "shear",
                   "reset", "resetTransform", "beginPath", "closePath", "moveTo",
                   "lineTo", "stroke", "fill", "rect", "clip", "arc", "arcTo",
                   "createLinearGradient", "createRadialGradient", "fillRect",
                   "strokeRect", "clearRect", "measureText", "isPointInPath",
                   "quadraticCurveTo", "bezierCurveTo", "onPaint", "image",
                   "createImageData", "drawImage", "getImageData", "putImageData",
                   "lineWidth", "lineCap", "lineJoin", "miterLimit", "strokeStyle",
                   "fillStyle", "globalAlpha", "globalCompositeOperation",
                   "shadowBlur", "shadowColor", "shadowOffsetX", "shadowOffsetY",
                   "font", "textAlign", "textBaseline", "canvasSize", "paintEnabled",
                   "markDirty", "path", "ellipse", "roundRect"},
    "MultiEffect": I | {"source", "autoPaddingEnabled", "paddingRect", "hasShadow",
                        "shadowEnabled", "shadowBlur", "shadowOpacity", "shadowColor",
                        "shadowScale", "shadowHorizontalOffset", "shadowVerticalOffset",
                        "brightness", "contrast", "saturation", "blurEnabled",
                        "blurMax", "blur", "blurMultiplier", "antialiasingMode",
                        "antialiasingQuality", "maskEnabled", "maskSource",
                        "maskInverted", "maskThresholdAtEdge", "hasBlur"},
    "Gradient": I | {"orientation", "stops"},
    "GradientStop": I | {"position", "color"},
    "Component": I | {"objectName"},
    "Window": I | {"visible", "width", "height", "color", "title", "flags",
                   "transientParent", "screen", "visibility"},
    "PanelWindow": I | {"anchors", "exclusiveZone", "exclusionMode",
                        "aboveWindows", "focusable", "color", "visible",
                        "screen", "mask", "margins", "backer"},
    "PopupWindow": I | {"visible", "width", "height", "implicitWidth",
                        "implicitHeight", "color", "screen", "anchor",
                        "window", "flags", "mask", "margins", "contentItem",
                        "grabFocus"},
    "IconImage": I | {"source", "asynchronous", "status", "mipmap",
                      "backer", "implicitSize", "actualSize", "sourceSize",
                      "fillMode", "paintedWidth", "paintedHeight"},
    "DragHandler": I | {"target", "acceptedButtons", "enabled", "active",
                        "activeTranslation", "point", "centroid",
                        "translation"},
    "Process": I | {"command", "cwd", "stdin", "stdout", "stderr", "running",
                    "environment", "exitCode", "stdoutEnabled",
                    "stderrEnabled"},
    "FileView": I | {"path", "text", "blockLoading", "blockWrites",
                     "watchChanges", "printErrors", "loaded", "adapter"},
    "SplitParser": I | {"splitMarker"},
    "IpcHandler": I | {"target", "active", "function"},
    "Singleton": I | {"objectName"},
    "Variants": I | {"model", "delegate"},
    "Repeater2": I | {"model", "delegate"},
    "ShellRoot": set(),
    "ScrollView": I | {"contentWidth", "contentHeight"},
}

SKIP_VALIDATE_TYPES = {"PropertyChanges"}   # dynamic target properties

QT_OBJECT_SIGNALS = {
    "MouseArea": {"clicked", "doubleClicked", "pressAndHold", "pressed",
                  "released", "canceled", "entered", "exited", "positionChanged",
                  "wheel", "containsMouseChanged", "hoveredChanged"},
    "Flickable": {"movementStarted", "movementEnded", "flickStarted",
                  "flickEnded", "isFlickingChanged"},
    "Timer": {"triggered"},
    "Loader": {"loaded"},
    "Process": {"exited", "started", "finished", "startedChanged",
                "exitedChanged", "runningChanged"},
    "FileView": {"loaded", "fileChanged", "saved", "loadFailed",
                 "loadedChanged", "pathChanged"},
    "Text": {"linkActivated", "linkHovered", "textChanged"},
    "ListView": {"currentIndexChanged", "countChanged"},
    "Repeater": {"itemAdded", "itemRemoved", "countChanged", "modelChanged"},
}

# ---------------------------------------------------------------------------
def tokenize(raw):
    """(kind, value, line) tokens for code; strings/comments collapsed."""
    toks, i, n, line = [], 0, len(raw), 1
    prev = ""          # last significant code token value (for regex detect)
    while i < n:
        c = raw[i]
        if c == "\n":
            line += 1; i += 1; continue
        if c in " \t\r":
            i += 1; continue
        if c == "/" and i + 1 < n and raw[i+1] == "/":
            j = raw.find("\n", i); i = n if j < 0 else j; continue
        if c == "/" and i + 1 < n and raw[i+1] == "*":
            j = raw.find("*/", i)
            end = n if j < 0 else j + 2
            line += raw.count("\n", i, end); i = end; continue
        if c in "\"'":
            q = c; i += 1
            while i < n and raw[i] != q:
                if raw[i] == "\\": i += 1
                elif raw[i] == "\n": line += 1
                i += 1
            i += 1
            toks.append(("str", "", line)); prev = "STR"; continue
        if c == "`":
            i += 1
            while i < n and raw[i] != "`":
                if raw[i] == "\\": i += 1
                elif raw[i] == "\n": line += 1
                i += 1
            i += 1
            toks.append(("str", "", line)); prev = "STR"; continue
        if c == "/" and (prev == "" or prev in "(,=:[!&|?{;+-*%<>~^" or
                         prev in ("return", "typeof", "case", "in", "of",
                                  "new", "delete", "void", "do", "else")):
            i += 1
            while i < n and raw[i] != "/":
                if raw[i] == "\\": i += 1
                elif raw[i] == "\n": line += 1
                i += 1
            i += 1
            while i < n and (raw[i].isalnum() or raw[i] == "_"): i += 1
            toks.append(("str", "", line)); prev = "STR"; continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (raw[j].isalnum() or raw[j] == "_"): j += 1
            toks.append(("id", raw[i:j], line)); prev = raw[i:j]; i = j
            continue
        if c.isdigit():
            j = i
            while j < n and (raw[j].isalnum() or raw[j] == "."): j += 1
            toks.append(("num", raw[i:j], line)); prev = "0"; i = j
            continue
        toks.append(("p", c, line)); prev = c; i += 1
    return toks

def code_only(toks):
    return " ".join(v if k in ("id", "num", "p") else "STR" for k, v, _ in toks)

DECL_RE = re.compile(
    r"\b(?:readonly\s+|default\s+|required\s+)*property\s+"
    r"(?:alias|[A-Za-z][\w.<>]*)\s+([a-zA-Z_]\w*)")
RO_DECL_RE = re.compile(
    r"\breadonly\s+property\s+(?:alias|[A-Za-z][\w.<>]*)\s+([a-zA-Z_]\w*)")
FUNC_RE = re.compile(r"\bfunction\s+([a-zA-Z_]\w*)\s*\(")
SIG_RE = re.compile(r"\bsignal\s+([a-zA-Z_]\w*)")
ROOT_RE = re.compile(r"\b([A-Z]\w*)\s*\{")
ID_RE = re.compile(r"\bid\s*:\s*(\w+)")

def parse_file(path):
    raw = open(path, encoding="utf-8").read()
    toks = tokenize(raw)
    co = code_only(toks)
    info = {
        "raw": raw, "toks": toks, "code": co, "path": path,
        "props": set(DECL_RE.findall(co)),
        "ro": set(RO_DECL_RE.findall(co)),
        "funcs": set(FUNC_RE.findall(co)),
        "sigs": set(SIG_RE.findall(co)),
        "ids": ID_RE.findall(co),
    }
    m = ROOT_RE.search(co)
    info["base"] = m.group(1) if m else "?"
    return info

def scan_objects(toks):
    """Yield QML objects: dict(type, line, assign, onx). Ternary-aware so
    `a ? b : c` colons are not mistaken for property assignments.  v19:
    also records each object's nearest enclosing QML type ("ptype") and
    every anchors.<x> token used inside it ("anchors_use") for the
    positioner-anchor check."""
    objects, stack, tern = [], [], 0
    for idx in range(len(toks)):
        k, v, ln = toks[idx]
        if k == "p" and v == "?":
            nxt = toks[idx+1] if idx + 1 < len(toks) else None
            if not (nxt and nxt[0] == "p" and nxt[1] in (".", "?")):
                tern += 1
            continue
        if k == "p" and v == ":":
            if tern > 0:
                tern -= 1
                continue                       # ternary colon, not assignment
        if (k == "id" and v == "anchors" and idx + 2 < len(toks)
                and toks[idx+1][0] == "p" and toks[idx+1][1] == "."
                and toks[idx+2][0] == "id"):
            #  anchors.<x> usage — attribute it to the owning QML object
            if stack and stack[-1][0] == "qml":
                stack[-1][1].setdefault("anchors_use", []).append(
                    (toks[idx+2][1], ln))
            continue
        if k == "p" and v == "{":
            prv = toks[idx-1] if idx else None
            if prv and prv[0] == "id" and prv[1][:1].isupper():
                obj = {"type": prv[1], "line": ln, "assign": [], "onx": [],
                       "isroot": not any(o.get("isroot") for o in objects)}
                obj["ptype"] = ""               # nearest enclosing QML type
                for fr in reversed(stack):
                    if fr[0] == "qml":
                        obj["ptype"] = fr[1]["type"]
                        break
                objects.append(obj)
                stack.append(("qml", obj))
            else:
                stack.append(("js", None))
        elif k == "p" and v in "}])":
            if stack: stack.pop()
        elif k == "p" and v in "[(":
            stack.append(("grp", None))
        elif k == "id":
            #  function declaration — attribute to the enclosing QML object
            #  (bodies are JS frames, so closures never double-count).
            if v == "function":
                nxt = toks[idx+1] if idx + 1 < len(toks) else None
                if nxt and nxt[0] == "id" and stack and stack[-1][0] == "qml":
                    stack[-1][1].setdefault("funcs_decl", []).append(
                        (nxt[1], nxt[2]))
                continue
            #  property declaration — record (name, line) on the owner so
            #  v6 can flag redeclarations in the same object.
            if v == "property":
                j = idx + 1
                if j < len(toks) and toks[j][0] == "id":
                    j += 1
                    if j < len(toks) and toks[j][0] == "p" and toks[j][1] == "<":
                        depth = 1; j += 1
                        while j < len(toks) and depth:
                            if toks[j][0] == "p" and toks[j][1] == "<": depth += 1
                            elif toks[j][0] == "p" and toks[j][1] == ">": depth -= 1
                            j += 1
                if j < len(toks) and toks[j][0] == "id" \
                   and stack and stack[-1][0] == "qml":
                    stack[-1][1].setdefault("props_decl", []).append(
                        (toks[j][1], toks[j][2]))
                continue
            prv = toks[idx-1] if idx else None
            if prv and prv[0] == "id" and prv[1] == "on":
                #  'Behavior on x' target — record BEFORE the colon check:
                #  `Behavior on size {` has no colon after the target.
                if stack and stack[-1][0] == "qml":
                    stack[-1][1].setdefault("behon", []).append((v, ln))
                continue
            nxt = toks[idx+1] if idx + 1 < len(toks) else None
            if not (nxt and nxt[0] == "p" and nxt[1] == ":"):
                continue
            if prv and prv[0] == "p" and prv[1] == ".":
                continue                       # grouped / attached (a.b:)
            if re.match(r"^on[A-Z]", v):
                # signal handler — record for check 6
                if stack and stack[-1][0] == "qml":
                    stack[-1][1]["onx"].append((v[2:], ln))
                continue
            if prv and prv[0] == "id" and prv[1] == "on":
                #  'Behavior on x' syntax — record the animation TARGET so
                #  check v5 can reject read-only / unknown properties.
                if stack and stack[-1][0] == "qml":
                    stack[-1][1].setdefault("behon", []).append((v, ln))
                continue
            back = toks[max(0, idx-4):idx]
            if any(b[0] == "id" and b[1] in ("property", "readonly", "default",
                    "required", "function", "signal", "component", "pragma")
                   for b in back):
                continue                       # declarations / annotations
            if stack and stack[-1][0] == "qml":
                if v == "id":
                    val = toks[idx+2] if idx + 2 < len(toks) else ("", "", 0)
                    stack[-1][1].setdefault("ids", []).append((val[1], ln))
                else:
                    stack[-1][1]["assign"].append((v, ln))
    return objects

def qmldir_map(d):
    out = {"types": set(), "singletons": {}}
    qmldir = os.path.join(d, "qmldir")
    if os.path.exists(qmldir):
        for line in open(qmldir, encoding="utf-8"):
            parts = line.split()
            if len(parts) >= 2 and parts[0] == "singleton":
                out["singletons"][parts[1]] = parts[2] if len(parts) > 2 else ""
            elif len(parts) >= 2:
                out["types"].add(parts[0])
    return out

def main():
    failures = 0
    notes = 0
    files, dirmap = {}, {}
    for base, dirs, fs in os.walk(ROOT):
        for f in sorted(fs):
            if f.endswith(".qml"):
                files[os.path.join(base, f)] = None
    for d in set(os.path.dirname(p) for p in files):
        dirmap[d] = qmldir_map(d)

    for path in files:
        files[path] = parse_file(path)

    #  v19: shader files are validated alongside the QML tree
    shader_files = []
    for base, dirs, fs in os.walk(ROOT):
        for f in sorted(fs):
            if f.endswith((".frag", ".vert")):
                shader_files.append(os.path.join(base, f))

    def local_type(name, d):
        if name in dirmap[d]["types"] and os.path.exists(os.path.join(d, name + ".qml")):
            return os.path.join(d, name + ".qml")
        m = re.search(r'import\s+"([^"]+)"', files[path]["raw"]) if False else None
        return None

    def resolve_import_dir(d, path, imp):
        return os.path.normpath(os.path.join(d, imp))

    def component_file(tname, path):
        """Resolve a local component QML file: same dir first, then any
        relative-import dir of the referencing file."""
        d = os.path.dirname(path)
        cand = os.path.join(d, tname + ".qml")
        if os.path.exists(cand):
            return cand
        for m in re.finditer(r'import\s+"([^"]+)"', files[path]["raw"]):
            if m.group(1).endswith(".js"):
                continue
            cand = os.path.join(os.path.normpath(os.path.join(d, m.group(1))), tname + ".qml")
            if os.path.exists(cand):
                return cand
        return None

    def props_of(tname, path, seen=None):
        """declared props + inherited via local base chain + whitelisted base."""
        tfile = component_file(tname, path)
        if tfile is None:
            return None
        seen = seen or set()
        if tname in seen: return set()
        seen.add(tname)
        info = files.get(tfile) or parse_file(tfile)
        out = set(info["props"])
        b = info["base"]
        if b in BASE_PROPS:
            out |= BASE_PROPS[b]
        elif component_file(b, tfile) is not None:
            out |= props_of(b, tfile, seen)
        return out

    def base_of(tname, path, seen=None):
        tfile = component_file(tname, path)
        if tfile is None:
            return "?"
        seen = seen or set()
        if tname in seen: return "?"
        seen.add(tname)
        info = files.get(tfile) or parse_file(tfile)
        b = info["base"]
        if b in BASE_PROPS or component_file(b, tfile) is None:
            return b
        return base_of(b, tfile, seen)

    def ro_of(tname, path, seen=None):
        """readonly custom props declared by a local component + base chain."""
        tfile = component_file(tname, path)
        if tfile is None:
            return set()
        seen = seen or set()
        if tname in seen: return set()
        seen.add(tname)
        info = files.get(tfile) or parse_file(tfile)
        out = set(info.get("ro", set()))
        b = info["base"]
        if component_file(b, tfile) is not None:
            out |= ro_of(b, tfile, seen)
        return out

    def funcs_sigs_of(tname, path):
        tfile = component_file(tname, path)
        if tfile is None:
            return None
        return files.get(tfile) or parse_file(tfile)

    for path, info in files.items():
        d = os.path.dirname(path)
        errs, warns = [], []

        # ---- v2: balance -------------------------------------------------
        depth = 0
        stack = []
        for k, v, ln in info["toks"]:
            if k != "p": continue
            if v in "{[(": stack.append((v, ln))
            elif v in "}])":
                if not stack: errs.append(f"{path}:{ln} unmatched {v}"); break
                o, ol = stack.pop()
                if "}])".index(v) != "{[(".index(o):
                    errs.append(f"{path}:{ln} {v} closes {o} from {ol}")
        for o, ol in stack:
            errs.append(f"{path}:{ol} unclosed {o}")

        # ---- v2: type resolution + imports --------------------------------
        #  Singletons declared in local qmldirs count as local types too —
        #  services/Bluetooth.qml shadows Quickshell.Bluetooth wherever the
        #  services module is imported.
        local = set(dirmap[d]["types"])
        for m in re.finditer(r'import\s+"([^"]+)"', info["raw"]):
            if not m.group(1).endswith(".js"):
                qd = qmldir_map(os.path.normpath(os.path.join(d, m.group(1))))
                local |= qd["types"] | set(qd["singletons"].keys())
        declared_comp = set(re.findall(r"\bcomponent\s+(\w+)\s*:", info["code"]))
        structural = set(o["type"] for o in scan_objects(info["toks"]))
        for t in structural:
            if t not in local and t not in declared_comp and t not in REQUIRED_MODULE \
               and t not in QT_BASE and t not in BASE_PROPS:
                errs.append(f"{path}: unresolved type '{t}'")
        mods = set(re.findall(r"import\s+(\S+)", info["raw"]))
        #  The tokenizer inserts spaces around '.', which left the X.Y
        #  member-access import check dead ("ToplevelManager . toplevels"
        #  never matched).  Re-join dots before scanning so usages inside
        #  JS function bodies are import-checked too (v17: the dock's
        #  windowsFor() walks ToplevelManager.toplevels).
        co_dots = re.sub(r"\s*\.\s*", ".", info["code"])
        for t in structural | set(re.findall(r"\b([A-Z]\w+)\.\w+", co_dots)):
            if t in local:
                continue   # a local type shadows the module type (services/
                           # Bluetooth.qml over Quickshell.Bluetooth, etc.)
            req = REQUIRED_MODULE.get(t)
            if req and req not in mods:
                errs.append(f"{path}: type '{t}' needs 'import {req}' (missing)")

        # ---- v3: property existence on local components -------------------
        for obj in scan_objects(info["toks"]):
            t = obj["type"]
            if t in SKIP_VALIDATE_TYPES:
                continue
            ok_props = props_of(t, path)
            if ok_props is None:
                continue                      # not a local component
            finfo = funcs_sigs_of(t, path)
            base = base_of(t, path)
            known_base = base in BASE_PROPS
            for name, ln in obj["assign"]:
                if name in ro_of(t, path):
                    errs.append(f'{path}:{ln} [{t}] cannot assign to '
                                f'read-only property "{name}"')
                    continue
                if name in ok_props or (finfo and name in finfo["funcs"]) \
                   or name in ("anchors", "data", "resources", "states",
                               "transitions", "transform", "component"):
                    continue
                if known_base and name in BASE_PROPS[base]:
                    continue
                errs.append(f'{path}:{ln} [{t}] cannot assign to non-existent '
                            f'property "{name}"')
            # ---- check 6: handlers on local components ---------------------
            sigs = set(finfo["sigs"]) if finfo else set()
            for name, ln in obj["onx"]:
                sig = name[0].lower() + name[1:]          # onClicked -> clicked
                chg = sig.endswith("Changed")
                if sig in sigs or sig in ok_props or \
                   (chg and sig[:-7] in ok_props) or \
                   sig in QT_OBJECT_SIGNALS.get(base, set()) or \
                   sig in QT_OBJECT_SIGNALS.get(t, set()):
                    continue
                errs.append(f'{path}:{ln} [{t}] handler "on{name}" does not '
                            f'match any signal or property')

        # ---- check 7: singleton member references --------------------------
        sing_files = {}
        sing_dirs = [d]
        for m in re.finditer(r'import\s+"([^"]+)"', info["raw"]):
            if not m.group(1).endswith(".js"):
                sing_dirs.append(os.path.normpath(os.path.join(d, m.group(1))))
        for sd in sing_dirs:
            if sd not in dirmap:
                dirmap[sd] = qmldir_map(sd)
            for sname, sfile in dirmap[sd]["singletons"].items():
                sp = os.path.join(sd, sfile or (sname + ".qml"))
                if os.path.exists(sp) and sname not in sing_files:
                    sing_files[sname] = files.get(sp) or parse_file(sp)
        toks = info["toks"]
        for idx in range(len(toks) - 2):
            a, dot, b = toks[idx], toks[idx+1], toks[idx+2]
            if a[0] == "id" and a[1] in sing_files and dot[0] == "p" \
               and dot[1] == "." and b[0] == "id":
                sinfo = sing_files[a[1]]
                if b[1] not in sinfo["props"] and b[1] not in sinfo["funcs"]:
                    errs.append(f'{path}:{a[2]} singleton {a[1]}.{b[1]} not declared')

        # ---- v4: PanelWindow root-level property whitelist -----------------
        #  Quickshell's PanelWindow does NOT expose every QQuickWindow
        #  property (empirically `opacity` failed on the user's build with
        #  'Cannot assign to non-existent property "opacity"'). Only props
        #  PROVEN on the user's build / linux-notch are allowed at roots.
        #  v18: the root indent is DETECTED (first content line after the
        #  root type's brace) instead of hard-coded to 4 spaces — the
        #  hyprland-dock port uses upstream's 2-space style, where nested
        #  members sit at 4 spaces and the old regex false-flagged every
        #  one of them as a root property.
        if info["base"] == "PanelWindow":
            code_lines = set(ln for k, v, ln in info["toks"]
                             if k in ("id", "num", "p"))
            root_indent = None
            mroot = re.search(r"^" + info["base"] + r"\s*\{",
                              info["raw"], re.M)
            if mroot:
                for tail in info["raw"][mroot.end():].split("\n"):
                    if not tail.strip() or tail.strip().startswith("//"):
                        continue
                    root_indent = len(tail) - len(tail.lstrip(" "))
                    break
            for ln2, rawline in enumerate(info["raw"].split("\n"), 1):
                if ln2 not in code_lines:
                    continue
                m2 = re.match(r"^(\s*)([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*:\s",
                              rawline)
                if not m2:
                    continue
                if root_indent is None or len(m2.group(1)) != root_indent:
                    continue                  # nested member, not a root prop
                name2 = m2.group(2)
                if name2 == "id":
                    continue
                if name2.startswith("on") and len(name2) > 2 and name2[2].isupper():
                    continue                  # signal/property handler
                if name2.split(".")[0] in PANEL_PROVEN or \
                   name2.startswith("WlrLayershell."):
                    continue
                errs.append(f'{path}:{ln2} [PanelWindow] root property '
                            f'"{name2}" is not build-proven — window roots '
                            f'accept only: {sorted(PANEL_PROVEN)}')
            if re.search(r"\bWlrLayershell\s*\.\s*[A-Z]", info["code"]):
                errs.append(f'{path}: WlrLayershell.<Capitalized> nested enum '
                            f'access is not portable — use standalone enum '
                            f'type (WlrKeyboardFocus, WlrLayer)')

        # ---- v5: 'Behavior on X' targets must be writable properties -------
        #  (Catches: Invalid property assignment: "size" is a read-only
        #  property — a Behavior WRITES to its target, so a readonly
        #  property can never carry one.)
        RO_QT = {"count", "item", "status", "progress", "containsMouse",
                 "containsPress", "hovered", "mouseX", "mouseY",
                 "paintedWidth", "paintedHeight"}
        GROUPS = {"anchors", "data", "resources", "states", "transitions",
                  "transform", "component"}
        for obj in scan_objects(info["toks"]):
            targets = obj.get("behon", [])
            if not targets:
                continue
            t = obj["type"]
            tfile = component_file(t, path)
            if tfile is not None:
                okp = props_of(t, path)
                rop = ro_of(t, path)
            elif t in BASE_PROPS:
                okp, rop = BASE_PROPS[t], set()
            else:
                continue                      # module type — unknown surface
            if obj.get("isroot"):
                #  Root object of a composite component: its effective type
                #  adds the component's own custom declarations on top of
                #  the base (e.g. DockIcon root = Rectangle + `size`).
                okp = okp | info["props"]
                rop = rop | info["ro"]
            #  ANY object may carry its own `property` declarations, and a
            #  Behavior legitimately targets them (the dock's `Behavior on
            #  mx / dx / strength / appear` are all custom-declared props
            #  on nested Items — refusing them was a false positive).
            okp = okp | set(n for n, _ in obj.get("props_decl", []))
            for name, ln in targets:
                seg = name.split(".")[0]
                if seg in GROUPS:
                    continue                  # anchors.xMargin etc — writable
                if seg in rop or seg in RO_QT:
                    errs.append(f'{path}:{ln} [{t}] "Behavior on {seg}": '
                                f'"{seg}" is a read-only property')
                    continue
                if seg not in okp:
                    errs.append(f'{path}:{ln} [{t}] "Behavior on {seg}": '
                                f'not a property of {t}')

        # ---- check 8: id collisions ---------------------------------------
        all_ids = [i for obj in scan_objects(info["toks"]) for i in obj.get("ids", [])]
        seen_ids = {}
        for i, ln in all_ids:
            if i in seen_ids:
                errs.append(f'{path}:{ln} duplicate id "{i}"')
            seen_ids[i] = True

        # ---- v6: duplicate methods / property declarations per object ------
        #  (Catches: @services/Hypr.qml[100:14]: Duplicate method name)
        for obj in scan_objects(info["toks"]):
            seen_fn = {}
            for fn, ln in obj.get("funcs_decl", []):
                if fn in seen_fn:
                    errs.append(f'{path}:{ln} duplicate method "{fn}" in '
                                f'{obj["type"]} (first at line {seen_fn[fn]})')
                else:
                    seen_fn[fn] = ln
            seen_pp = {}
            for pp, ln in obj.get("props_decl", []):
                if pp in seen_pp:
                    errs.append(f'{path}:{ln} duplicate property declaration '
                                f'"{pp}" in {obj["type"]} '
                                f'(first at line {seen_pp[pp]})')
                else:
                    seen_pp[pp] = ln

        # ---- v7: <Prop>Changed handlers on module-type objects -------------
        #  (Catches: @island/StatGraph.qml[101:9]: Cannot assign to
        #   non-existent property "onValuesChanged" — a Changed handler
        #   attached to a child object for a property that lives elsewhere,
        #   typically on the file root.)
        for obj in scan_objects(info["toks"]):
            t = obj["type"]
            if t in SKIP_VALIDATE_TYPES or t not in BASE_PROPS:
                continue              # local comps already covered (check 6)
            surface = set(BASE_PROPS[t])
            surface |= set(n for n, _ in obj.get("props_decl", []))
            if obj.get("isroot"):
                surface |= info["props"]   # file root: own declarations too
            for name, ln in obj["onx"]:
                if not name.endswith("Changed") or len(name) <= 7:
                    continue          # onPaint / onClicked — signals, skip
                target = name[0].lower() + name[1:-7]
                if target in surface:
                    continue
                if (target + "Changed") in QT_OBJECT_SIGNALS.get(t, set()):
                    continue          # curated signal list (e.g. FileView fileChanged)
                errs.append(f'{path}:{ln} [{t}] handler "on{name}" does not '
                            f'match any property of {t} ("{target}" is not a '
                            f'property here)')

        # ---- v8: arrow bodies must be expressions or {blocks} -------------
        #  `x => if (c) f()` is a JS syntax error (statement bodies need
        #  braces).  (Catches: @island/IslandWindow.qml[568:55]: Unexpected
        #  token `if')
        ARROW_BAN = {"if", "for", "while", "switch", "try", "do",
                     "return", "throw", "const", "let", "var",
                     "function", "class", "else"}
        toks = info["toks"]
        for idx in range(len(toks) - 2):
            if toks[idx][0] == "p" and toks[idx][1] == "=" \
               and toks[idx+1][0] == "p" and toks[idx+1][1] == ">":
                nxt = toks[idx+2]
                if nxt[0] == "id" and nxt[1] in ARROW_BAN:
                    errs.append(f'{path}:{nxt[2]} arrow body cannot be a '
                                f'statement ("=> {nxt[1]}") — use "=> {{ ... }}"')

        # ---- v9: duplicate signal handlers on one object -----------------
        #  (Catches: two `onVisibleChanged:` blocks on the same Window —
        #   the engine rejects the second assignment and the whole file
        #   fails to load. Happens when handlers get added in two places.)
        for obj in scan_objects(info["toks"]):
            seen_h = {}
            for h, ln in obj["onx"]:
                if h in seen_h:
                    errs.append(f'{path}:{ln} duplicate signal handler "on{h}" '
                                f'in {obj["type"]} (first at line {seen_h[h]})')
                else:
                    seen_h[h] = ln

        # ---- v10: object declared through an id (`lower.Upper {`) ---------
        #  `id.Type { }` is invalid QML — ids are not types/namespaces.
        #  (Catches: 'settingsWindow.AboutGroup - settingsWindow is neither
        #   a type nor a namespace' — inline components must be referenced
        #   by bare name; type-qualified names start uppercase.)
        for idx in range(len(toks) - 3):
            a, b, c, d = toks[idx], toks[idx+1], toks[idx+2], toks[idx+3]
            if (a[0] == "id" and a[1][:1].islower()
                    and b[0] == "p" and b[1] == "."
                    and c[0] == "id" and c[1][:1].isupper()
                    and d[0] == "p" and d[1] == "{"):
                errs.append(f'{path}:{c[2]} object declared as "{a[1]}.{c[1]}" '
                            f'— ids are not types/namespaces; write "{c[1]} {{ }}"')

        # ---- v11: infinite-loop probes must be started ---------------------
        #  (Catches: stats stuck at 0 — a Process with `while :; do ...`
        #  in its shell command that is never given running: true.)
        raw = info["raw"]
        if re.search(r"while\s*(:|true)\s*;", raw):
            if not (re.search(r"\brunning\s*:\s*true\b", raw)
                    or re.search(r"\.[ \t]*running[ \t]*=[ \t]*true\b", raw)):
                errs.append(f'{path}:? infinite shell-loop probe ("while :; do") '
                            f'is never started — add "running: true" to the '
                            f'Process or set <id>.running = true')

        # ---- v12: local type names colliding with Qt built-ins -------------
        #  (Catches: a singleton named Keys.qml would shadow QtQuick's
        #  attached Keys type in every file importing its module —
        #  Keys.onPressed silently breaks / the type becomes ambiguous.)
        local_names = {os.path.splitext(os.path.basename(path))[0]}
        local_names.update(re.findall(r"\bcomponent\s+(\w+)\s*:", raw))
        for bad in sorted(local_names & QT_BUILTIN_NAMES):
            errs.append(f'{path}:? type name "{bad}" collides with a Qt '
                        f'built-in (attached/element) type — rename it, e.g. '
                        f'Keys -> Hotkeys')

        # ---- v13: images fed arbitrary model paths must downscale ----------
        #  (Catches: "Killed" — the wallpaper picker decoded every 4K
        #  wallpaper at full resolution, gigabytes in seconds.)
        for m in re.finditer(r"\bImage\s*\{", raw):
            ln = raw[:m.start()].count("\n") + 1
            start = m.end() - 1
            depth = 0
            end = start
            for i in range(start, len(raw)):
                if raw[i] == "{":
                    depth += 1
                elif raw[i] == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            block = raw[start:end + 1]
            if re.search(r"\bsource\s*:\s*[^\n]*modelData", block) \
               and not re.search(r"\bsourceSize\s*:", block):
                errs.append(f'{path}:{ln} Image fed modelData without '
                            f'sourceSize — full-resolution decode of '
                            f'arbitrary files OOM-kills the shell; add '
                            f'sourceSize: Qt.size(w * 2, h * 2)')

        # ---- v15: Keys convenience handlers are not portable -------------
        #  (Catches: 'Cannot assign to non-existent property
        #  "onPageDownPressed"' on the user's Quickshell build — while its
        #  PageUp twin resolved. Only onPressed/onReleased/
        #  onShortcutOverride exist everywhere; route every other key
        #  through Keys.onPressed + event.key.)
        for idx in range(len(toks) - 2):
            a, b, c = toks[idx], toks[idx + 1], toks[idx + 2]
            if (a[0] == "id" and a[1] == "Keys"
                    and b[0] == "p" and b[1] == "."
                    and c[0] == "id" and c[1].startswith("on")
                    and len(c[1]) > 2 and c[1][2].isupper()):
                name = c[1][2:]
                if name not in ("Pressed", "Released", "ShortcutOverride"):
                    errs.append(f'{path}:{c[2]} Keys.on{name} — attached '
                                f'convenience handlers are not portable '
                                f'(onPageDownPressed was missing on the '
                                f'user\'s build while onPageUpPressed '
                                f'resolved); use Keys.onPressed with '
                                f'explicit event.key checks')

        # ---- v19a: positioner anchors (Row/Column direct children) -------
        #  (Catches: "QML Row at ControlCenterCard.qml[494:17]: Cannot
        #  specify left, right, horizontalCenter, fill or centerIn anchors
        #  for items inside Row. Row will not function." — 5x per
        #  relayout; the anchors are silently DROPPED, so the layout
        #  never looks broken in code review, only at runtime.)
        ROW_BAN = {"left", "right", "horizontalCenter", "fill", "centerIn"}
        COL_BAN = {"top", "bottom", "verticalCenter", "fill", "centerIn"}
        for obj in scan_objects(info["toks"]):
            ptype = obj.get("ptype", "")
            ban = ROW_BAN if ptype == "Row" else \
                  COL_BAN if ptype == "Column" else None
            if not ban:
                continue
            for ax, ln3 in obj.get("anchors_use", []):
                if ax in ban:
                    errs.append(
                        f'{path}:{ln3} [{obj["type"]}] anchors.{ax} on a '
                        f'direct child of {ptype} — "{ptype} will not '
                        f'function"; use an Item wrapper, spacer widths or '
                        f'the positioner\'s own alignment instead')

        # ---- v19b: ShaderEffect uniform buf order -------------------------
        #  Both the QML property declaration order and the shader's
        #  `uniform buf` member order describe ONE shared std140 buffer
        #  layout — a mismatch renders garbage without any error.
        #  Samplers (variant/var) are matched by name and excluded.
        if re.search(r"\.(frag|vert)\b", raw):
            fx_objs = [o for o in scan_objects(info["toks"])
                       if o["type"] == "ShaderEffect"]
            mfx = re.search(r"\bShaderEffect\s*\{", raw)
            if len(fx_objs) == 1 and mfx:
                start = mfx.end() - 1
                depth = 0
                end = start
                for i in range(start, len(raw)):
                    if raw[i] == "{":
                        depth += 1
                    elif raw[i] == "}":
                        depth -= 1
                        if depth == 0:
                            end = i
                            break
                block = raw[start:end + 1]
                decls = re.findall(
                    r"\bproperty\s+(variant|var|alias|real|int|double|bool|"
                    r"vector2d|point|size|vec2|color|matrix4x4|quaternion)\s+"
                    r"(\w+)\s*:", block)
                buf_names = [nm for ty, nm in decls
                             if ty not in ("variant", "var", "alias")]
                mfr = re.search(r"(\w+\.(?:frag|vert))\b", raw)
                ftarget = None
                if mfr:
                    for sp2 in shader_files:
                        if os.path.basename(sp2) == mfr.group(1):
                            ftarget = sp2
                            break
                members = None
                if ftarget:
                    ftext = open(ftarget, encoding="utf-8",
                                 errors="ignore").read()
                    mb = re.search(r"uniform\s+buf\s*\{([^}]*)\}", ftext)
                    if mb:
                        members = [m for m in re.findall(
                            r"(?:mat4|mat3|float|int|uint|bool|vec2|vec3|"
                            r"vec4|ivec2|ivec3|ivec4|uvec2|dvec2)\s+(\w+)\s*;",
                            mb.group(1))
                            if m not in ("qt_Matrix", "qt_Opacity")]
                if members is not None and members != buf_names:
                    errs.append(
                        f'{path}:? ShaderEffect uniform order mismatch with '
                        f'{os.path.basename(ftarget)}: QML declares '
                        f'{buf_names} but the buf block lists {members} — '
                        f'reorder the properties (or the shader block) so '
                        f'both sides match')

        # ---- v19c: Hyprland.dispatch is centralized -----------------------
        #  (Catches: a stray raw dispatch — Lua Hyprland evaluates every
        #  request as `return hl.dispatch(<text>)`, so only services/
        #  Hypr.qml, which speaks hl.dsp.* + classic fallbacks, may call
        #  it directly; anything else bypasses the self-healing forms.)
        if os.path.basename(path) != "Hypr.qml" and \
           re.search(r"\bHyprland\s*\.\s*dispatch\b", info["code"]):
            errs.append(f'{path}:? Hyprland.dispatch outside services/'
                        f'Hypr.qml — route it through Hypr.dispatch() / '
                        f'Hypr.switchTo() so the Lua/mainline strategy '
                        f'stays centralized')

        for e in errs:
            print("FAIL", e); failures += 1
        for w in warns:
            print("NOTE", w); notes += 1

    # ---- v19d: GLSL shaders (*.frag / *.vert) ----------------------------
    #  qsb compiles Vulkan-style GLSL and transpiles to ES 310 / SPIR-V
    #  itself; `#version 440` must be the first non-comment line. Without
    #  it qsb parses GLSL ES 1.00 and rejects the source ("ES shaders for
    #  SPIR-V require version 310 or higher" + "'float': type requires
    #  declaration of default precision qualifier") — liquidglass.frag
    #  shipped exactly like that, so the dock silently lost its glass.
    for spath in shader_files:
        lines = open(spath, encoding="utf-8", errors="ignore").read().split("\n")
        first = ""
        for line in lines:
            s = line.strip()
            if not s or s.startswith(("//", "/*", "*")):
                continue
            first = s
            break
        if not re.match(r"#version\s+440(\s|$)", first):
            print(f"FAIL {spath}: shader must start with '#version 440' "
                  f"(missing/old versions are parsed as GLSL ES 1.00 and "
                  f"rejected by qsb); found: {first[:48]!r}")
            failures += 1
        body = re.sub(r"//[^\n]*", " ", "\n".join(lines))
        body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
        for legacy in ("varying", "attribute", "texture2D", "gl_FragColor",
                       "gl_FragData"):
            if re.search(r"\b" + legacy + r"\b", body):
                print(f"FAIL {spath}: legacy GLSL token '{legacy}' — qsb "
                      f"needs Vulkan-style GLSL 440 (in/out, texture(), "
                      f"fragColor)")
                failures += 1

    print(f"Checked {len(files)} QML files + {len(shader_files)} shaders (v19)")
    if failures == 0:
        print("ALL CHECKS PASSED")
    else:
        print(f"{failures} problems found")
        sys.exit(1)

main()
