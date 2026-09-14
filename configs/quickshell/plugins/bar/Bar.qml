import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "widgets"

// Registry-driven left/center/right widget placement (quickshell Phase 2):
// each section's model comes from `barConfig.layout.<section>`, resolved
// against `barWidgetRegistry` for the Component to instantiate. Still this
// repo's own hover-driven panel mechanism throughout — upstream's Bar.qml
// (1842 lines) is click/drag-reorder-driven with its own popout-coordinator
// API (clickTargets/requestPopout/releasePopout/activePopout); this file
// keeps the hoverOpen/hoverTriggerExit/hoverPanelEnter/hoverPanelExit/
// hoverCloseTimer/activePanel model built earlier instead of porting that.
PanelWindow {
  id: root

  screen: modelData
  required property var modelData

  // Injected by shell.qml, matching upstream's configureBar() pattern.
  property QtObject pluginRegistry: null
  property QtObject barWidgetRegistry: null
  property var barConfig: null
  // Named shellHost, not shell: the outer ShellRoot's own `id: shell`
  // would otherwise shadow this property when referenced unqualified from
  // within shell.qml's own `Bar { shell: shell }`-style assignment,
  // silently binding this to itself (still-null) instead of the ancestor.
  property QtObject shellHost: null
  // Which output shell.qml considers main; empty means "no opinion", in which
  // case every bar renders the full layout (the single-monitor case, and the
  // safe answer if screen names ever stop matching).
  property string mainScreenName: ""

  // False on every output except the main one. Secondary bars render
  // `barConfig.secondaryLayout` instead of the full layout.
  readonly property bool isMainScreen: mainScreenName === ""
    || !modelData
    || String(modelData.name) === mainScreenName

  // Tray.qml's ownedByOmarchy() filter reads this as the plain
  // {left,center,right} layout object, not the {layout:{...}} wrapper.
  // BarSection reads it too, so this is the single place that decides which
  // of the two layouts a given screen's bar draws.
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

  // Hyprland leaves an already-mapped layer surface at its old global
  // position when its monitor moves within the layout — undock, and the bar
  // keeps drawing at the previous origin or off-screen entirely. The guard
  // pulses `remapping` once the move settles, and folding it into `visible`
  // is what unmaps and remaps the surface so the compositor re-places it.
  // See Ui/ScreenMoveRemap.qml.
  ScreenMoveRemap { id: screenGuard; window: root }
  visible: !screenGuard.remapping

  readonly property bool vertical: false
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property string fontFamily: Style.resolvedFontFamily
  // Glyph-bearing widgets must read THIS, not fontFamily. Bar widgets use
  // bar.fontFamily for both label text and icons; sweeping only
  // Style.font.family would have left every bar glyph on the
  // user-selectable family, which is the exact breakage the split exists
  // to prevent.
  readonly property string iconFontFamily: Style.font.iconFamily
  readonly property bool foregroundAnimationEnabled: true
  readonly property color barForeground: Color.bar.text
  readonly property color background: Color.bar.background
  readonly property color urgent: Color.bar.active

  function run(cmd) {
    Util.execDetached(cmd)
  }

  // Shared popup state: only one widget panel open at a time, and opening a
  // new one closes whatever was open. Each panel widget checks
  // `bar.activePanel === moduleName` for visibility and calls
  // `bar.togglePanel(moduleName)` on click, instead of managing its own
  // independent bool — otherwise every widget's popup is fully independent
  // and they pile up on screen with no way to dismiss them.
  property string activePanel: ""

  function togglePanel(id) {
    activePanel = activePanel === id ? "" : id
  }

  function closePanel(id) {
    if (activePanel === id) activePanel = ""
  }

  // Hover-driven panel open/close. Trigger (WidgetButton) and panel
  // (Ui/HoverPanel) each report their own hover state independently — they
  // are separate wl_surfaces with a geometric gap between them (the bar's
  // margin down to the panel), so both go false while the pointer is in
  // transit between them. `hoverCloseTimer`'s grace period is what keeps the
  // panel open across that gap instead of closing on every trigger-to-panel
  // move; it only actually closes once neither side is hovered when it
  // fires.
  property bool triggerHovered: false
  property bool panelHovered: false

  Timer {
    id: hoverCloseTimer
    // Sized for the gap between a trigger and its panel, which is now 4px
    // for every widget: centre-section panels open directly under their own
    // trigger (HoverPanel.anchorWidget), and the top margin no longer
    // double-counted the bar's exclusive zone. The clock used to be the
    // outlier at ~950px and drove this number; it is no longer, so 350ms is
    // now generous rather than barely sufficient.
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

  // `quickshell ipc -p ~/.config/quickshell call bar open <moduleName>` /
  // `close` / `toggle`. Scriptable panel control (bind a key to open the
  // network panel, drive the shell from a test harness) for the same reason
  // Panel widgets get a moduleName in the first place.
  IpcHandler {
    target: "bar"
    function open(panel: string): void { root.activePanel = panel }
    function close(): void { root.activePanel = "" }
    function toggle(panel: string): void { root.togglePanel(panel) }
  }

  // Bumped whenever anything that can move a widget horizontally changes.
  // BarWidget watches this to republish its laid-out x, which is what lets a
  // panel anchor under its own trigger. It exists because `mapToItem` is not
  // a reactive expression: QML cannot track the chain of ancestor positions
  // it walks, so a plain binding on it evaluates once — before RowLayout has
  // laid anything out — and then stays stale forever. That is precisely how
  // the earlier attempt at under-trigger anchoring failed; the coordinate
  // math was right and the reactivity was missing. Rather than trying to
  // make the binding reactive, the sections announce when they moved.
  property int layoutRevision: 0

  // Minimal hover tooltip: a small label anchored under whichever widget last
  // asked for one. Not pixel-tracked to the cursor like omarchy-shell's
  // PanelToolTip, just anchored to the hovered item's position.
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
  //
  // This was a RowLayout with a fillWidth spacer either side of the centre
  // group. Those spacers divide the *leftover* space equally, which centres the
  // middle section between the two side sections — not on the display. With a
  // full right-hand cluster and a nearly empty left one, that put the clock
  // about 230px left of the actual centre of the screen, and moved it every
  // time a right-hand widget appeared or vanished.
  //
  // Three anchored rows instead: left to the left edge, right to the right
  // edge, centre to the screen's own centre. The centre now holds still no
  // matter what the other two do.
  //
  // THE SPACERS WERE ALSO THE ONLY THING KEEPING THE CLUSTERS APART. Removing
  // them fixed the centring and removed all arbitration with it: three rows
  // anchored to three different edges have no idea the other two exist, so a
  // long window title on the left or a full tray on the right would simply
  // draw straight through the clock. Layouts do not collide; they overlap in
  // silence, which is the worst way for this to fail.
  //
  // So each side sits in a holder that is bounded by the centre cluster's own
  // edge and clips. The side sections keep their natural width until they
  // would reach the centre, and are cut off at exactly the point where they
  // would start overwriting it. There is no binding loop: `centerSection.x`
  // depends on its own implicit width and the bar's width, never on the
  // holders.
  Item {
    anchors.fill: parent

    // The gap a side cluster must leave before the centre one. One item gap
    // reads as "these are separate groups" without wasting bar.
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
        // Anchored to the holder's RIGHT edge, so when the holder is narrower
        // than the cluster it is the leftmost (oldest, most permanent) icons
        // that get clipped and the rightmost that stay — matching the layout
        // note in shell.qml about transient widgets growing leftward.
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.bar.itemGap
        onXChanged: root.layoutRevision++
        onWidthChanged: root.layoutRevision++

        BarSection { bar: root; section: "right" }
      }
    }
  }

  // A full-screen click-to-dismiss catcher used to live here. It made sense
  // when panels opened on click, but panels are hover-driven now (open on
  // trigger-hover, close once neither trigger nor panel is hovered, after
  // hoverCloseTimer's grace period) — a full-screen WlrLayer.Top surface
  // that appears the instant any panel-enabled icon is merely hovered would
  // swallow clicks everywhere on screen for as long as a panel is open,
  // which is now most of the time you're near the bar. Removed; hover
  // already closes the panel shortly after the pointer leaves both the
  // trigger and the panel, which covers "clicked elsewhere" too since
  // reaching another window means leaving both hover zones first.

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
