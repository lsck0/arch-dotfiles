import QtQuick
import qs.Commons

// Base item every bar widget extends: bar (host Bar instance), moduleName
// (widget id, currently unused without a settings registry), settings
// (unused for the same reason, kept so upstream widget code needs no edits).
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // This widget's laid-out x within the bar, in bar-content coordinates.
  // Set `HoverPanel.anchorWidget: root` on a panel to have it open centred
  // beneath its own trigger instead of at the bar's right edge.
  //
  // Republished imperatively, never as a binding. `mapToItem` walks a chain
  // of ancestor positions that QML does not treat as binding dependencies,
  // so `property real barX: mapToItem(...).x` evaluates once during
  // construction — before RowLayout has positioned anything, when every x is
  // still 0 — and never updates. It looks like a coordinate bug and is
  // actually a reactivity gap; see Bar.qml's layoutRevision. Recomputing on
  // every signal that can move this widget is what closes it.
  property real barX: 0

  // Always deferred, never computed inline. The signals that tell us the
  // layout changed (a section's onXChanged, say) fire *during* the layout
  // pass, while the ancestor chain mapToItem walks is still half-settled —
  // reading it there returns the pre-layout position and then nothing fires
  // again. Coalescing into a single read one frame later is what makes the
  // value correct as well as fresh; this was the second bug on this path,
  // after the stale-binding one.
  function refreshBarX() { barXSettle.restart() }

  Timer {
    id: barXSettle
    interval: 16
    repeat: false
    onTriggered: {
      if (!root.bar || !root.bar.contentItem) return
      root.barX = root.mapToItem(root.bar.contentItem, 0, 0).x
    }
  }

  // Own geometry: fires when this widget's content resizes (a clock ticking
  // to a wider minute, a stats string growing a digit) and when the section
  // repositions it.
  onXChanged: refreshBarX()
  onWidthChanged: refreshBarX()

  // Ancestor geometry: a widget's own x does NOT change when the section
  // containing it slides sideways because a *different* section grew, so
  // watching only the above would drift. layoutRevision covers that case.
  Connections {
    target: root.bar
    enabled: root.bar !== null
    function onLayoutRevisionChanged() { root.refreshBarX() }
    function onWidthChanged() { root.refreshBarX() }
  }

  // At Component.onCompleted the enclosing RowLayout has not run its layout
  // pass yet, so an immediate read returns 0 for everything.
  Component.onCompleted: refreshBarX()
}
