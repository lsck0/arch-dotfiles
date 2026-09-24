import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "widgets"
import "widgets/BuiltinWidgets.js" as BuiltinWidgets

// Registry-driven left/center/right widget placement (quickshell Phase 2): each section's model comes from `barConfig.layout.<section>`, and BarSection resolves each entry id to a .qml URL through `pluginRegistry` (falling back to its own map of the widgets that ship in widgets/).
PanelWindow {
  id: root

  screen: modelData
  required property var modelData

  // Injected by shell.qml, matching upstream's configureBar() pattern.
  property QtObject pluginRegistry: null
  property var barConfig: null
  // Named shellHost, not shell: the outer ShellRoot's own `id: shell` would otherwise shadow this property when referenced unqualified from within shell.qml's own `Bar { shell: shell }`-style assignment, silently binding this to itself (still-null) instead of the ancestor.
  property QtObject shellHost: null
  // Which output shell.qml considers main; empty means "no opinion", in which case every bar renders the full layout (the single-monitor case, and the safe answer if screen names ever stop matching).
  property string mainScreenName: ""

  // False on every output except the main one.
  readonly property bool isMainScreen: mainScreenName === ""
    || !modelData
    || String(modelData.name) === mainScreenName

  // Tray.qml's ownedByOmarchy() filter reads this as the plain {left,center,right} layout object, not the {layout:{...}} wrapper.
  readonly property var layoutConfig: {
    if (!barConfig) return null
    if (!isMainScreen && barConfig.secondaryLayout) return barConfig.secondaryLayout
    return barConfig.layout || null
  }

  anchors {
    top: true
    left: true
    right: true
  }
  exclusiveZone: Style.bar.sizeHorizontal
  implicitHeight: Style.bar.sizeHorizontal
  color: "transparent"

  // Hyprland leaves an already-mapped layer surface at its old global position when its monitor moves within the layout — undock, and the bar keeps drawing at the previous origin or off-screen entirely.
  ScreenMoveRemap { id: screenGuard; window: root }
  visible: !screenGuard.remapping

  readonly property bool vertical: false
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property string fontFamily: Style.resolvedFontFamily
  // Glyph-bearing widgets must read THIS, not fontFamily.
  readonly property string iconFontFamily: Style.font.iconFamily
  readonly property bool foregroundAnimationEnabled: true
  readonly property color barForeground: Color.bar.text
  readonly property color background: Color.bar.background
  readonly property color urgent: Color.bar.active

  function run(cmd) {
    Util.execDetached(cmd)
  }

  // BarSection's cold-start id → file map mirrors the widget manifests, so check once per session that the two still agree rather than trusting the comment asking the next person to edit both.
  Connections {
    target: root.pluginRegistry
    enabled: root.pluginRegistry !== null
    function onScanFinished() {
      BuiltinWidgets.checkDrift(root.pluginRegistry.installedPlugins, console.warn)
    }
  }

  // Shared popup state: only one widget panel open at a time, and opening a new one closes whatever was open.
  property string activePanel: ""

  function togglePanel(id) {
    activePanel = activePanel === id ? "" : id
  }

  function closePanel(id) {
    if (activePanel === id) activePanel = ""
  }

  // Hover-driven panel open/close.
  property bool triggerHovered: false
  property bool panelHovered: false

  Timer {
    id: hoverCloseTimer
    // Sized for the gap between a trigger and its panel, which is now 4px for every widget: centre-section panels open directly under their own trigger (HoverPanel.anchorWidget), and the top margin no longer double-counted the bar's exclusive zone.
    interval: 350
    onTriggered: {
      if (!root.triggerHovered && !root.panelHovered) root.activePanel = ""
    }
  }

  function hoverOpen(id) {
    hoverCloseTimer.stop()
    if (root.activePanel !== id) {
      root.activePanel = id
      root.panelHovered = false
    }
    root.triggerHovered = true
  }

  function hoverTriggerExit(id) {
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

  // `quickshell ipc -p ~/.config/quickshell call bar open <moduleName>` / `close` / `toggle`.
  readonly property string ipcScreenName: modelData ? String(modelData.name) : ""
  readonly property bool ownsGlobalIpcTarget: {
    if (ipcScreenName === "") return true
    if (mainScreenName !== "") return ipcScreenName === mainScreenName
    // No opinion on which output is main (shell.qml only reports that with no screens at all): fall back to the first one, so exactly one bar still answers to `bar`.
    var screens = Quickshell.screens
    return screens.length === 0 || String(screens[0].name) === ipcScreenName
  }
  readonly property string ipcTarget: ownsGlobalIpcTarget ? "bar" : "bar-" + ipcScreenName

  IpcHandler {
    target: root.ipcTarget
    function open(panel: string): void { root.activePanel = panel }
    function close(): void { root.activePanel = "" }
    function toggle(panel: string): void { root.togglePanel(panel) }
    // Which panel this particular bar has open, so a script driving several outputs can tell them apart without guessing.
    function state(): string { return root.activePanel }
  }

  // Bumped whenever anything that can move a widget horizontally changes.
  property int layoutRevision: 0

  // Minimal hover tooltip: a small label anchored under whichever widget last asked for one.
  property var tooltipItem: null
  property string tooltipText: ""

  function showTooltip(item, text) {
    if (!text) return
    tooltipItem = item
    tooltipText = text
  }

  function hideTooltip(item) {
    if (tooltipItem === item) {
      tooltipItem = null
      tooltipText = ""
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.background
  }

  // THE CENTRE IS ANCHORED TO THE SCREEN, NOT SPLIT BETWEEN THE SIDES.
  Item {
    anchors.fill: parent

    // The gap a side cluster must leave before the centre one.
    readonly property int keepClear: Style.bar.itemGap * 2

    Item {
      id: leftHolder
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
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
        // Anchored to the holder's RIGHT edge, so when the holder is narrower than the cluster it is the leftmost (oldest, most permanent) icons that get clipped and the rightmost that stay — matching the layout note in shell.qml about transient widgets growing leftward.
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.bar.itemGap
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection { bar: root; section: "right" }
      }
    }
  }

  // A full-screen click-to-dismiss catcher used to live here.

  Rectangle {
    visible: root.tooltipItem !== null
    color: Color.background
    border.color: Color.accent
    border.width: 1
    radius: Style.cornerRadius
    height: tooltipLabel.implicitHeight + Style.spacing.sm * 2
    width: tooltipLabel.implicitWidth + Style.spacing.md * 2
    x: {
      if (!root.tooltipItem) return 0
      var pos = root.tooltipItem.mapToItem(root.contentItem, 0, root.tooltipItem.height)
      return Math.max(0, Math.min(root.width - width, pos.x))
    }
    y: root.barSize + 2

    Text {
      id: tooltipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.tooltipText
      color: Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
