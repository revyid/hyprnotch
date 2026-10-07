pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

//  ─────────────────────────────────────────────────────────────────
//  THE DOCK — a faithful port of nick-friedrich/hyprland-dock into
//  HyprNotch.  https://github.com/nick-friedrich/hyprland-dock
//
//  Upstream behavior, unchanged:
//    · pinned .desktop apps with real icons, running dots, tooltips
//    · Gaussian pointer-distance magnification
//    · left-click focus-or-launch, right-click context menu
//      (Add Application / Remove / Auto-Hide / New Window / Close)
//    · drag pinned icons to reorder — the others slide aside
//    · fuzzy-search app picker popup
//    · four dock positions (bottom / top / left / right), vertical
//      docks, full-length mode, optional reserved screen space
//    · auto-hide with a 3 px screen-edge reveal strip
//
//  Hyprnotch deltas, all deliberate and listed here:
//    · settings come from services/Config.qml (~/.config/hyprnotch/
//      config.json → dock section) via DockHost, not a dock.json file;
//      "Dock Settings" in the menu opens Settings → Dock
//    · the window is a full-length strip on the bar axis (upstream:
//      a compact window).  The BAR keeps upstream's exact compact
//      geometry — the strip exists so the input mask below can make
//      the empty area click-through
//    · input mask = the bar + magnification headroom instead of the
//      whole window — clicks pass through the empty strip (upstream
//      eats the whole band above the bar)
//    · frosted-blur material (r24): the Liquid Glass shader was
//      removed by user request — the bar is translucent and the
//      compositor blurs it (layerrule blur on namespace
//      hyprnotch-dock, applied in start.sh / togglable in Settings)
//    · hideDelay is configurable (upstream: fixed 800 ms)
//  ─────────────────────────────────────────────────────────────────

PanelWindow {
  id: root

  required property var settings
  //  hyprnotch: per-screen gate (dock.enabled + primary-display-only)
  property bool screenEnabled: true

  signal reorderRequested(int from, int to)
  signal pinRequested(string desktopId)
  signal unpinRequested(string desktopId)
  signal autoHideRequested(bool enabled)
  signal settingsRequested()

  property int dragSource: -1
  property int dragTarget: -1
  property int openMenuCount: 0
  property bool autoHideRevealed: false

  readonly property int iconSize: settings.iconSize || 52
  readonly property real magnification: settings.magnification || 1.65
  readonly property real magnificationRadius: settings.magnificationRadius || 110
  readonly property int edgeMargin: settings.margin === undefined ? 10 : settings.margin
  readonly property real backgroundOpacity: {
    var value = Number(settings.backgroundOpacity)
    return settings.backgroundOpacity === undefined || isNaN(value)
      ? 0.88
      : Math.max(0, Math.min(1, value))
  }
  readonly property bool reserveSpace: settings.reserveSpace === undefined ? true : settings.reserveSpace
  readonly property bool autoHide: settings.autoHide === undefined ? false : settings.autoHide
  readonly property int hideDelay: settings.hideDelay === undefined ? 800 : settings.hideDelay
  readonly property string clickAction: settings.clickAction || "focus-or-launch"
  readonly property string requestedPosition: settings.position || "bottom"
  readonly property string position: ["top", "bottom", "left", "right"].indexOf(requestedPosition) >= 0
    ? requestedPosition
    : "bottom"
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool fullLength: settings.fullLength === undefined ? false : settings.fullLength
  readonly property var pinned: settings.pinned || []
  readonly property int itemSize: iconSize + 14
  readonly property int reservedSize: iconSize + 24 + edgeMargin
  readonly property int mainPadding: 10
  readonly property int revealThickness: 3
  readonly property int crossExtent: vertical
    ? Math.ceil(iconSize * magnification + 80) + edgeMargin
    : Math.ceil(iconSize * magnification + 48) + edgeMargin
  readonly property bool keepAutoHideOpen: windowPointer.hovered
    || appPicker.visible || openMenuCount > 0 || dragSource >= 0
  readonly property bool dockShown: !autoHide || autoHideRevealed
  readonly property real pointerPosition: !pointer.hovered
    ? -10000
    : vertical
      ? pointer.point.position.y - dockLayout.y
      : pointer.point.position.x - dockLayout.x

  //  How far the input mask extends past the bar on the side the icons
  //  grow toward — magnified icons must stay clickable.
  readonly property real magHeadroom: Math.ceil(iconSize * (magnification - 1)) + 20

  function reorderOffset(index) {
    if (dragSource < dragTarget && index > dragSource && index <= dragTarget)
      return -itemSize
    if (dragSource > dragTarget && index >= dragTarget && index < dragSource)
      return itemSize
    return 0
  }

  function updateDragTarget(position) {
    dragTarget = Math.max(0, Math.min(pinned.length - 1, Math.floor(position / itemSize)))
  }

  function finishDrag() {
    var from = dragSource
    var to = dragTarget
    dragSource = -1
    dragTarget = -1
    if (from >= 0 && to >= 0 && from !== to)
      reorderRequested(from, to)
  }

  function updateAutoHideState() {
    if (!autoHide) {
      hideTimer.stop()
      autoHideRevealed = false
    } else if (keepAutoHideOpen) {
      hideTimer.stop()
      autoHideRevealed = true
    } else if (autoHideRevealed) {
      hideTimer.restart()
    }
  }

  onAutoHideChanged: updateAutoHideState()
  onKeepAutoHideOpenChanged: updateAutoHideState()

  visible: screenEnabled

  //  Full-length strip on the bar axis (hyprnotch delta — see header):
  //  bottom/top also anchor left+right, left/right also anchor top+bottom.
  anchors {
    top: position === "top" || vertical
    bottom: position === "bottom" || vertical
    left: !vertical
    right: !vertical
  }
  implicitWidth: vertical ? crossExtent : 0
  implicitHeight: vertical ? 0 : crossExtent
  color: "transparent"
  exclusionMode: reserveSpace && !autoHide ? ExclusionMode.Normal : ExclusionMode.Ignore
  WlrLayershell.exclusiveZone: reserveSpace && !autoHide ? reservedSize : 0
  WlrLayershell.namespace: "hyprnotch-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {
    item: root.dockShown ? maskArea : revealStrip
  }

  Timer {
    id: hideTimer

    interval: root.hideDelay
    onTriggered: if (root.autoHide && !root.keepAutoHideOpen)
      root.autoHideRevealed = false
  }

  //  ── Input mask: the bar + headroom on the grow side ─────────────
  //  Everything else in the strip stays click-through.
  Item {
    id: maskArea

    x: root.vertical
      ? (root.position === "left"
         ? dockBackground.x - 12
         : dockBackground.x - root.magHeadroom)
      : dockBackground.x - 12
    y: !root.vertical
      ? (root.position === "top"
         ? dockBackground.y - 12
         : dockBackground.y - root.magHeadroom)
      : dockBackground.y - 12
    width: root.vertical
      ? dockBackground.width + root.magHeadroom + 12
      : dockBackground.width + 24
    height: !root.vertical
      ? dockBackground.height + root.magHeadroom + 12
      : dockBackground.height + 24
  }

  Item {
    id: revealStrip

    x: root.position === "right" ? parent.width - width : 0
    y: root.position === "bottom" ? parent.height - height : 0
    width: root.vertical ? root.revealThickness : parent.width
    height: root.vertical ? parent.height : root.revealThickness
  }

  //  ── The bar — upstream's exact compact geometry ─────────────────
  //  Upstream hosts this in a window sized to the bar; here it is
  //  self-sized and centered inside the strip (same pixels on screen).
  Rectangle {
    id: dockBackground

    x: root.vertical
      ? root.position === "left" ? root.edgeMargin : parent.width - width - root.edgeMargin
      : (parent.width - width) / 2
    y: root.vertical
      ? (parent.height - height) / 2
      : root.position === "top" ? root.edgeMargin : parent.height - height - root.edgeMargin
    width: root.vertical ? root.iconSize + 24 : dockLayout.implicitWidth + root.mainPadding * 2
    height: root.vertical ? dockLayout.implicitHeight + root.mainPadding * 2 : root.iconSize + 24
    radius: 20
    color: Qt.rgba(0.08, 0.09, 0.11, root.backgroundOpacity)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)
    transform: Translate {
      x: !root.autoHide || root.dockShown
        ? 0
        : root.position === "left"
          ? -(dockBackground.width + root.edgeMargin)
          : root.position === "right" ? dockBackground.width + root.edgeMargin : 0
      y: !root.autoHide || root.dockShown
        ? 0
        : root.position === "top"
          ? -(dockBackground.height + root.edgeMargin)
          : root.position === "bottom" ? dockBackground.height + root.edgeMargin : 0

      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.28)
    }

    Grid {
      id: dockLayout

      // Offset the layout toward the screen edge so the icon itself, rather
      // than the icon-plus-indicator slot, is centered in the background.
      x: root.vertical
        ? root.position === "left" ? 6 : parent.width - implicitWidth - 6
        : (parent.width - implicitWidth) / 2
      y: root.vertical
        ? (parent.height - implicitHeight) / 2
        : root.position === "top" ? 6 : parent.height - implicitHeight - 6

      // Keep one spare cell so a settings reload cannot transiently reduce the
      // grid capacity before the repeater updates its delegates.
      columns: root.vertical ? 1 : Math.max(1, root.pinned.length + 1)
      rows: root.vertical ? Math.max(1, root.pinned.length + 1) : 1

      Repeater {
        model: root.pinned

        DockItem {
          required property string modelData
          required property int index

          desktopId: modelData
          itemIndex: index
          slotSize: root.itemSize
          iconSize: root.iconSize
          magnification: root.magnification
          magnificationRadius: root.magnificationRadius
          pointerPosition: root.pointerPosition
          clickAction: root.clickAction
          autoHide: root.autoHide
          position: root.position
          vertical: root.vertical
          reorderOffset: root.reorderOffset(index)
          onDragStarted: itemIndex => {
            root.dragSource = itemIndex
            root.dragTarget = itemIndex
          }
          onDragMoved: mainPosition => root.updateDragTarget(mainPosition)
          onDragFinished: root.finishDrag()
          onAddApplicationRequested: appPicker.open()
          onRemoveRequested: desktopId => root.unpinRequested(desktopId)
          onAutoHideToggled: enabled => root.autoHideRequested(enabled)
          onSettingsRequested: root.settingsRequested()
          onContextMenuVisibilityChanged: visible => {
            root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
          }
        }
      }
    }

    HoverHandler {
      id: pointer
    }
  }

  DockAppPicker {
    id: appPicker

    anchorItem: dockBackground
    position: root.position
    pinned: root.pinned
    onApplicationSelected: desktopId => root.pinRequested(desktopId)
  }

  HoverHandler {
    id: windowPointer
  }
}
