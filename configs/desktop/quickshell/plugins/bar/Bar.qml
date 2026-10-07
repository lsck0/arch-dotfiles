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

  // {left, center, right} widget names, read by BarSection.qml
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
  readonly property color barForeground: Color.bar.text
  readonly property color background: Color.bar.background
  readonly property color urgent: Color.bar.active

  // quiet: no spectrum, glow or flicker while a fullscreen window hides the bar or power saver is on
  readonly property var hyprMonitor: modelData ? Hyprland.monitorFor(modelData) : null
  readonly property bool fullscreenBelow: !!hyprMonitor && !!hyprMonitor.activeWorkspace
    && hyprMonitor.activeWorkspace.hasFullscreen === true
  readonly property bool quiet: Power.saver || fullscreenBelow

  // only one panel open at a time
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
    // grace for the pointer to travel from the trigger into the drawer
    interval: 350
    onTriggered: {
      if (!root.triggerHovered && !root.panelHovered) root.activePanel = ""
    }
  }

  // hover intent: a pointer crossing the bar opens nothing, an open panel switches at once
  property string pendingPanel: ""

  Timer {
    id: hoverIntentTimer
    interval: 130
    onTriggered: root.openHovered(root.pendingPanel)
  }

  function openHovered(id) {
    root.pendingPanel = ""
    if (root.activePanel !== id) {
      root.activePanel = id
      root.panelHovered = false
    }
    root.triggerHovered = true
  }

  function hoverOpen(id) {
    hoverCloseTimer.stop()
    if (root.activePanel !== "") {
      hoverIntentTimer.stop()
      openHovered(id)
      return
    }
    root.pendingPanel = id
    hoverIntentTimer.restart()
  }

  function hoverTriggerExit(id) {
    if (root.pendingPanel === id) {
      hoverIntentTimer.stop()
      root.pendingPanel = ""
    }
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

  // qs ipc call bar open|close|toggle <panel>
  readonly property string ipcScreenName: modelData ? String(modelData.name) : ""
  readonly property bool ownsGlobalIpcTarget: {
    if (ipcScreenName === "") return true
    if (mainScreenName !== "") return ipcScreenName === mainScreenName
    // no main screen known: first output owns `bar`
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

  // bumped when widgets can move horizontally
  property int layoutRevision: 0

  property var tooltipItem: null
  property string tooltipText: ""
  // shown only after the pointer rests, like PanelToolTip
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
    color: Color.accent
    // drawers continue this rule at the same alpha (Ui/DockShape.qml)
    opacity: Style.surface.ruleAlpha
    layer.enabled: Style.fx.glow > 0 && !root.quiet
    layer.effect: Glow { shadowColor: Color.accent }
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
      width: Math.max(0, Math.min(leftSection.implicitWidth,
                                  centerSection.x - x - parent.keepClear))

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

    RowLayout {
      id: centerSection
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.bar.itemGap
      onXChanged: root.layoutRevision++
      onWidthChanged: root.layoutRevision++

      BarSection { bar: root; section: "center" }
    }

    Item {
      id: rightHolder
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.max(0, Math.min(rightSection.implicitWidth,
                                  parent.width - (centerSection.x + centerSection.width)
                                    - parent.keepClear))

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
  }

  // a popup, the bar window is exactly barSize tall and would clip it; same surface as Ui/PanelToolTip.qml
  PopupWindow {
    id: tooltipWindow
    visible: root.tooltipShown && root.tooltipItem !== null && root.visible
    color: "transparent"
    implicitWidth: tooltipSurface.width
    implicitHeight: tooltipSurface.height
    anchor.window: root
    anchor.rect.x: {
      if (!root.tooltipItem) return 0
      var pos = root.tooltipItem.mapToItem(root.contentItem, 0, 0)
      return Math.max(0, Math.min(root.width - tooltipSurface.width, pos.x))
    }
    anchor.rect.y: root.barSize + Style.spacing.xxs

    BorderSurface {
      id: tooltipSurface
      color: Color.tooltip.background
      borderSpec: Border.flat(Color.tooltip.border, Style.normalBorderWidth)
      radius: Style.shape.surface
      leftPadding: Style.spacing.controlPaddingX
      rightPadding: Style.spacing.controlPaddingX
      topPadding: Style.spacing.controlPaddingY
      bottomPadding: Style.spacing.controlPaddingY
      height: tooltipRow.implicitHeight + contentTopInset + contentBottomInset
      width: tooltipRow.implicitWidth + contentLeftInset + contentRightInset

      Row {
        id: tooltipRow
        x: tooltipSurface.contentLeftInset
        y: tooltipSurface.contentTopInset
        spacing: Style.spacing.xs

        Text {
          anchors.baseline: tooltipLabel.baseline
          textFormat: Text.PlainText
          text: ">"
          color: Color.accent
          opacity: Style.emphasis.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
