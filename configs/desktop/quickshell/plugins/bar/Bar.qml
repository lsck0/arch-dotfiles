import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "widgets"
import "../Plugins.js" as Plugins

PanelWindow {
  id: root

  screen: modelData
  required property var modelData

  // injected by shell.qml, not `shell`: shell.qml's `id: shell` would shadow it
  property QtObject shellHost: null
  // empty: every bar renders the full layout
  property string mainScreenName: ""

  readonly property bool isMainScreen: mainScreenName === ""
    || !modelData
    || String(modelData.name) === mainScreenName

  readonly property var layoutConfig: isMainScreen ? Plugins.bar : Plugins.barSecondary

  anchors {
    top: true
    left: true
    right: true
  }
  exclusiveZone: Style.bar.sizeHorizontal
  // hyprland_windowrules.lua blurs it by this name
  WlrLayershell.namespace: "quickshell-bar"
  implicitHeight: Style.bar.sizeHorizontal
  color: "transparent"

  // hyprland leaves stale layer position after monitor moves
  ScreenMoveRemap { id: screenGuard; window: root }
  visible: !screenGuard.remapping

  readonly property bool vertical: false
  // read by HoverPanel and PopupCard, the bar is always on top
  readonly property string position: "top"
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property string fontFamily: Style.resolvedFontFamily
  // glyph widgets must use this, not fontFamily
  readonly property string iconFontFamily: Style.font.iconFamily
  readonly property bool foregroundAnimationEnabled: true
  readonly property color barForeground: Colors.bar.text
  readonly property color background: Colors.bar.background
  readonly property color urgent: Colors.bar.active

  readonly property var hyprMonitor: modelData ? Hyprland.monitorFor(modelData) : null
  readonly property bool fullscreenBelow: !!hyprMonitor && !!hyprMonitor.activeWorkspace
    && hyprMonitor.activeWorkspace.hasFullscreen === true
  readonly property bool quiet: Power.saver || fullscreenBelow

  property string activePanel: ""

  function togglePanel(id) {
    activePanel = activePanel === id ? "" : id
  }

  function closePanel(id) {
    if (activePanel === id) activePanel = ""
  }

  property bool triggerHovered: false
  property bool panelHovered: false

  Timer {
    id: hoverCloseTimer
    // grace for the pointer to reach the drawer
    interval: 350
    onTriggered: {
      if (!root.triggerHovered && !root.panelHovered) root.activePanel = ""
    }
  }

  // drawers snap on a handoff, so a switch reads as one surface, not a close-reopen
  property bool panelSwitching: false
  Timer {
    id: switchSettle
    interval: 0
    onTriggered: root.panelSwitching = false
  }

  // brushing across a widget edge must not thrash open<->open
  property string pendingPanel: ""
  Timer {
    id: switchIntent
    interval: 70
    onTriggered: root.applyHoverOpen(root.pendingPanel)
  }

  function hoverOpen(id) {
    hoverCloseTimer.stop()
    root.pendingPanel = id
    if (root.activePanel === "" || root.activePanel === id) {
      switchIntent.stop()
      root.applyHoverOpen(id)
    } else {
      switchIntent.restart()
    }
  }

  function applyHoverOpen(id) {
    if (root.pendingPanel !== id) return
    if (root.activePanel !== id) {
      root.panelSwitching = root.activePanel !== ""
      root.activePanel = id
      root.panelHovered = false
      if (root.panelSwitching) switchSettle.restart()
    }
    root.triggerHovered = true
  }

  function hoverTriggerExit(id) {
    if (root.pendingPanel === id) { switchIntent.stop(); root.pendingPanel = "" }
    if (root.activePanel !== id) return
    root.triggerHovered = false
    hoverCloseTimer.restart()
  }

  function hoverPanelEnter(id) {
    if (root.activePanel !== id) return
    root.panelHovered = true
    hoverCloseTimer.stop()
  }

  function hoverPanelExit(id) {
    if (root.activePanel !== id) return
    root.panelHovered = false
    hoverCloseTimer.restart()
  }

  readonly property string ipcScreenName: modelData ? String(modelData.name) : ""
  readonly property bool ownsGlobalIpcTarget: {
    if (ipcScreenName === "") return true
    if (mainScreenName !== "") return ipcScreenName === mainScreenName
    var screens = Quickshell.screens
    return screens.length === 0 || String(screens[0].name) === ipcScreenName
  }
  readonly property string ipcTarget: ownsGlobalIpcTarget ? "bar" : "bar-" + ipcScreenName

  IpcHandler {
    target: root.ipcTarget
    function open(panel: string): void { root.activePanel = panel }
    function close(): void { root.activePanel = "" }
    function toggle(panel: string): void { root.togglePanel(panel) }
    function state(): string { return root.activePanel }
  }

  property int layoutRevision: 0

  property var tooltipItem: null
  property string tooltipText: ""
  property bool tooltipShown: false

  Timer {
    id: tooltipDelay
    interval: 400
    onTriggered: root.tooltipShown = root.tooltipItem !== null
  }

  function showTooltip(item, text) {
    if (!text) return
    tooltipItem = item
    tooltipText = text
    if (!tooltipShown) tooltipDelay.restart()
  }

  function hideTooltip(item) {
    if (tooltipItem === item) {
      tooltipDelay.stop()
      tooltipShown = false
      tooltipItem = null
      tooltipText = ""
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.background
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.fx.bracketWidth)
    color: Colors.accent
    // over the widgets: a hover fill must not cover the rule the drawer neck joins
    z: 1
    // Ui/DockShape.qml repeats this alpha
    opacity: Style.surface.ruleAlpha
    layer.enabled: Style.fx.glow > 0 && !root.quiet
    layer.effect: Glow { shadowColor: Colors.accent }
  }

  Scanlines { shown: !root.quiet }

  // centre anchored to the screen, not split between sides
  Item {
    anchors.fill: parent

    readonly property int keepClear: Style.bar.itemGap * 2

    Item {
      id: leftHolder
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      // reserved before center, which centres itself in whatever gap remains
      width: Math.max(0, Math.min(leftSection.implicitWidth, parent.width - parent.keepClear))

      RowLayout {
        id: leftSection
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.bar.itemGap
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection { bar: root; section: "left" }
      }
    }

    // right reserves its natural width first (it is the crowded side with many
    // icons plus media); left and center then share whatever remains, so a wide
    // right section never gets clipped behind a dead-centered clock/weather
    Item {
      id: rightHolder
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.max(0, Math.min(rightSection.implicitWidth,
                                  parent.width - leftHolder.width - parent.keepClear))

      RowLayout {
        id: rightSection
        // right-anchored so the leftmost icons clip first
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.bar.itemGap
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection { bar: root; section: "right" }
      }
    }

    // centred in the gap between the side holders, not the raw screen centre,
    // so it slides out of the way (and clips itself) before it ever forces
    // rightHolder to clip a widget like Media
    Item {
      id: centerHolder
      readonly property real gapLeft: leftHolder.x + leftHolder.width + parent.keepClear
      readonly property real gapRight: rightHolder.x - parent.keepClear
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.max(0, Math.min(centerSection.implicitWidth, gapRight - gapLeft))
      x: gapLeft + Math.max(0, (gapRight - gapLeft - width) / 2)

      RowLayout {
        id: centerSection
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.bar.itemGap
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection { bar: root; section: "center" }
      }
    }
  }

  // a popup: the bar window is barSize tall and would clip it
  PopupWindow {
    id: tooltipWindow
    visible: root.tooltipShown && root.tooltipItem !== null && root.visible
    color: "transparent"
    implicitWidth: tooltipSurface.width
    implicitHeight: tooltipSurface.height
    // quickshell's qmltypes stub PopupAnchor as opaque, so qmllint cannot see window or rect
    anchor.window: root // qmllint disable missing-property
    anchor.rect.x: { // qmllint disable unqualified unresolved-type
      if (!root.tooltipItem) return 0
      var pos = root.tooltipItem.mapToItem(root.contentItem, 0, 0)
      return Math.max(0, Math.min(root.width - tooltipSurface.width, pos.x))
    }
    anchor.rect.y: root.barSize + Style.spacing.xxs

    BorderSurface {
      id: tooltipSurface
      color: Colors.tooltip.background
      borderSpec: Border.flat(Colors.tooltip.border, Style.normalBorderWidth)
      radius: Style.shape.surface
      leftPadding: Style.spacing.controlPaddingX
      rightPadding: Style.spacing.controlPaddingX
      topPadding: Style.spacing.controlPaddingY
      bottomPadding: Style.spacing.controlPaddingY
      height: tooltipRow.implicitHeight + contentTopInset + contentBottomInset
      width: tooltipRow.implicitWidth + contentLeftInset + contentRightInset

      opacity: root.tooltipShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
      transform: Translate {
        y: root.tooltipShown ? 0 : -Style.space(6)
        Behavior on y { NumberAnimation { duration: Style.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
      }

      Row {
        id: tooltipRow
        x: tooltipSurface.contentLeftInset
        y: tooltipSurface.contentTopInset
        spacing: Style.spacing.xs

        Text {
          anchors.baseline: tooltipLabel.baseline
          textFormat: Text.PlainText
          text: ">"
          color: Colors.accent
          opacity: Style.emphasis.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          text: root.tooltipText
          color: Colors.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
