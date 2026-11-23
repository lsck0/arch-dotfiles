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

  property QtObject shellHost: null
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
  WlrLayershell.namespace: "quickshell-bar"
  implicitHeight: Style.bar.sizeHorizontal
  color: "transparent"

  ScreenMoveRemap { id: screenGuard; window: root }
  visible: !screenGuard.remapping

  readonly property var hyprMonitor: modelData ? Hyprland.monitorFor(modelData) : null
  readonly property bool fullscreenBelow: !!hyprMonitor && !!hyprMonitor.activeWorkspace
    && hyprMonitor.activeWorkspace.hasFullscreen === true
  readonly property bool quiet: Power.saver || fullscreenBelow

  property string activePanel: ""
  // the HoverPanel on screen, open or still closing; the toasts and desktop widgets read its rect to hide under it
  property var activePanelWindow: null
  // the docked PopupCard on screen
  property var activePopup: null
  // a docked panel or popup grows out of the bar: the hairline stops for its width and runs on down its sides
  readonly property var dock: activePanelWindow ? activePanelWindow.screenRect : activePopup ? activePopup.dockRect : null
  property string pinnedPanel: ""
  property bool keyboardPanel: false
  property var panelNames: []

  function panelRegister(id) {
    if (panelNames.indexOf(id) === -1) panelNames = panelNames.concat([id])
  }

  function panelUnregister(id) {
    panelNames = panelNames.filter(function(name) { return name !== id })
  }

  function panelShow(id, pinned, keyboard) {
    hoverCloseTimer.stop()
    switchIntent.stop()
    pinnedPanel = pinned ? id : ""
    keyboardPanel = keyboard
    if (activePanel === id) return
    panelSwitching = activePanel !== ""
    activePanel = id
    panelHovered = false
    if (panelSwitching) switchSettle.restart()
  }

  function panelHide() {
    hoverCloseTimer.stop()
    switchIntent.stop()
    pendingPanel = ""
    pinnedPanel = ""
    keyboardPanel = false
    activePanel = ""
  }

  function togglePanel(id) {
    if (activePanel === id) panelHide()
    else panelShow(id, true, true)
  }

  function closePanel(id) {
    if (activePanel === id) panelHide()
  }

  function panelClick(id) {
    if (panelNames.indexOf(id) === -1) return
    if (activePanel === id && pinnedPanel === id) panelHide()
    else panelShow(id, true, false)
  }

  property bool triggerHovered: false
  property bool panelHovered: false

  Timer {
    id: hoverCloseTimer
    interval: 350
    onTriggered: {
      if (root.pinnedPanel !== "") return
      if (!root.triggerHovered && !root.panelHovered) root.panelHide()
    }
  }

  property bool panelSwitching: false
  Timer {
    id: switchSettle
    interval: 0
    onTriggered: root.panelSwitching = false
  }

  readonly property int hoverOpenDelayMs: 140
  readonly property int hoverSwitchDelayMs: 70

  property string pendingPanel: ""
  Timer {
    id: switchIntent
    interval: root.hoverOpenDelayMs
    onTriggered: root.applyHoverOpen(root.pendingPanel)
  }

  function hoverOpen(id) {
    if (root.pinnedPanel === id) {
      root.triggerHovered = true
      return
    }
    hoverCloseTimer.stop()
    root.pendingPanel = id
    if (root.activePanel === id) {
      switchIntent.stop()
      root.applyHoverOpen(id)
      return
    }
    switchIntent.interval = root.activePanel === "" ? root.hoverOpenDelayMs : root.hoverSwitchDelayMs
    switchIntent.restart()
  }

  function applyHoverOpen(id) {
    if (root.pendingPanel !== id || root.pinnedPanel === id) return
    if (root.activePanel !== id) root.panelShow(id, false, false)
    root.triggerHovered = true
  }

  function hoverTriggerExit(id) {
    if (root.pendingPanel === id) { switchIntent.stop(); root.pendingPanel = "" }
    if (root.activePanel !== id) {
      // a sweep across another trigger stopped the close timer and never opened that panel: the open one still closes
      if (root.activePanel !== "" && root.pinnedPanel === "" && !root.triggerHovered && !root.panelHovered) hoverCloseTimer.restart()
      return
    }
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

  function panelUnknown(panel) {
    return "unknown panel " + panel + ", panels: " + panelNames.join(" ")
  }

  IpcHandler {
    target: root.ipcTarget
    function open(panel: string): string {
      if (root.panelNames.indexOf(panel) === -1) return root.panelUnknown(panel)
      root.panelShow(panel, true, true)
      return ""
    }
    function close(): void { root.panelHide() }
    function toggle(panel: string): string {
      if (root.panelNames.indexOf(panel) === -1) return root.panelUnknown(panel)
      root.togglePanel(panel)
      return ""
    }
    function state(): string { return root.activePanel }
    function list(): string { return root.panelNames.join(" ") }
  }

  property int layoutRevision: 0

  property var tooltipItem: null
  property string tooltipNext: ""
  // the shown widget and text: they change only when the tooltip shows, and stay while it fades out
  property var tooltipAnchor: null
  property string tooltipText: ""
  property bool tooltipShown: false

  function placeTooltip() {
    tooltipAnchor = tooltipItem
    tooltipText = tooltipNext
    tooltipShown = true
  }

  Timer {
    id: tooltipDelay
    interval: 400
    onTriggered: if (root.tooltipItem !== null) root.placeTooltip()
  }

  function showTooltip(item, text) {
    if (!text) return
    tooltipItem = item
    tooltipNext = text
    if (tooltipShown) placeTooltip()
    else tooltipDelay.restart()
  }

  function hideTooltip(item) {
    if (tooltipItem === item) {
      tooltipDelay.stop()
      tooltipShown = false
      tooltipItem = null
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Colors.bar.background
  }

  component Hairline: Rectangle {
    anchors.bottom: parent.bottom
    height: Style.surface.borderWidth
    color: Colors.edge
    z: 1
  }
  Hairline { width: root.dock ? root.dock.x : root.width }
  Hairline { visible: root.dock !== null; x: root.dock ? root.dock.x + root.dock.width : 0; width: root.width - x }

  Scanlines { shown: !root.quiet }

  Item {
    id: rowArea
    anchors.fill: parent

    readonly property int keepClear: Style.bar.itemGap * 2
    readonly property int leftInset: Style.spacing.sm

    // one drop pass over all three sections: the lowest barPriority widget anywhere goes first until the left row, the
    // center row and the right row fit side by side with keepClear between them; ties go center, right, left
    readonly property var dropped: {
      const sections = [centerWidgets, rightWidgets, leftWidgets]
      var candidates = []
      var widths = [0, 0, 0]
      var counts = [0, 0, 0]
      for (let s = 0; s < sections.length; s++) {
        for (const widget of sections[s].candidates) {
          candidates.push({ section: s, index: widget.index, width: widget.width, priority: widget.priority, order: widget.order })
          widths[s] += widget.width
          counts[s]++
        }
      }
      candidates.sort(function(a, b) { return a.priority - b.priority || a.section - b.section || a.order - b.order })

      function rowWidth(s) { return counts[s] === 0 ? 0 : widths[s] + (counts[s] - 1) * Style.bar.itemGap }
      function needed() {
        return rowArea.leftInset + rowWidth(2) + rowArea.keepClear
          + (counts[0] > 0 ? rowWidth(0) + rowArea.keepClear : 0) + rowWidth(1)
      }

      var out = [{}, {}, {}]
      for (let i = 0; i < candidates.length && needed() > rowArea.width; i++) {
        const widget = candidates[i]
        out[widget.section][widget.index] = true
        widths[widget.section] -= widget.width
        counts[widget.section]--
      }
      return out
    }

    Item {
      id: leftHolder
      anchors.left: parent.left
      anchors.leftMargin: parent.leftInset
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.max(0, Math.min(leftSection.implicitWidth, parent.width - parent.keepClear))

      RowLayout {
        id: leftSection
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection {
          id: leftWidgets
          bar: root
          section: "left"
          dropped: rowArea.dropped[2]
          spacing: Style.bar.itemGap
        }
      }
    }

    Item {
      id: rightHolder
      readonly property real room: Math.max(0, parent.width - leftHolder.x - leftHolder.width - parent.keepClear
        - (centerSection.implicitWidth > 0 ? centerSection.implicitWidth + parent.keepClear : 0))
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.min(rightSection.implicitWidth, room)

      RowLayout {
        id: rightSection
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection {
          id: rightWidgets
          bar: root
          section: "right"
          dropped: rowArea.dropped[1]
          spacing: Style.bar.itemGap
        }
      }
    }

    Item {
      id: centerHolder
      // both sections at their widest so far: a workspace or a tray icon coming or going then leaves the centre where
      // it is. A bar of another width (scale, monitor) starts over; when the centre does not fit the widest gap, the
      // sections as they are now win
      property real leftWidest: 0
      property real rightWidest: 0
      readonly property real leftWidth: leftHolder.width
      readonly property real rightWidth: rightHolder.width
      readonly property real barWidth: parent.width
      onLeftWidthChanged: leftWidest = Math.max(leftWidest, leftWidth)
      onRightWidthChanged: rightWidest = Math.max(rightWidest, rightWidth)
      onBarWidthChanged: {
        leftWidest = leftWidth
        rightWidest = rightWidth
      }
      readonly property real gapLeftWidest: leftHolder.x + Math.max(leftWidth, leftWidest) + parent.keepClear
      readonly property real gapRightWidest: barWidth - Math.max(rightWidth, rightWidest) - parent.keepClear
      readonly property bool fitsWidest: gapRightWidest - gapLeftWidest >= centerSection.implicitWidth
      readonly property real gapLeft: fitsWidest ? gapLeftWidest : leftHolder.x + leftWidth + parent.keepClear
      readonly property real gapRight: fitsWidest ? gapRightWidest : rightHolder.x - parent.keepClear
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      width: Math.max(0, Math.min(centerSection.implicitWidth, gapRight - gapLeft))
      // on the midpoint of the gap between the left and the right section
      x: gapLeft + Math.max(0, gapRight - gapLeft - width) / 2

      RowLayout {
        id: centerSection
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection {
          id: centerWidgets
          bar: root
          section: "center"
          dropped: rowArea.dropped[0]
          spacing: Style.bar.itemGap
        }
      }
    }
  }

  PopupWindow {
    // mapped until the fade out ends
    visible: root.visible && root.tooltipAnchor !== null && (root.tooltipShown || tooltipSurface.opacity > 0)
    color: "transparent"
    implicitWidth: tooltipSurface.width
    implicitHeight: tooltipSurface.height
    anchor.window: root // qmllint disable missing-property
    anchor.rect.x: { // qmllint disable unqualified unresolved-type
      if (!root.tooltipAnchor) return 0
      var pos = root.tooltipAnchor.mapToItem(root.contentItem, 0, 0)
      return Math.max(0, Math.min(root.width - tooltipSurface.width, pos.x))
    }
    anchor.rect.y: Style.bar.sizeHorizontal + Style.spacing.xs

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
      FadeBehavior on opacity {}
      transform: Translate {
        y: root.tooltipShown ? 0 : -Style.motion.travel
        FadeBehavior on y { entering: targetValue === 0 }
      }

      Row {
        id: tooltipRow
        x: tooltipSurface.contentLeftInset
        y: tooltipSurface.contentTopInset
        spacing: Style.spacing.xs

        Label {
          anchors.baseline: tooltipLabel.baseline
          text: ">"
          color: Colors.accentText
          opacity: Style.emphasis.faint
          caption: true
        }
        Label {
          id: tooltipLabel
          // tray items supply their own tooltip text, which can be any length
          width: Math.min(implicitWidth, Style.panelWidth.wide)
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          text: root.tooltipText
          color: Colors.tooltip.text
          caption: true
        }
      }
    }
  }
}
