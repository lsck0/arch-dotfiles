import QtQuick
import qs.Commons
import qs.Ui

// A hairline rule between groups of bar widgets.
//
// WHY A WIDGET AND NOT A PROPERTY OF THE SECTION. Grouping has to be the
// layout's decision, not the bar's: which widgets belong together is exactly
// the thing that changes as widgets are added, and baking a grouping rule into
// BarSection would mean editing QML every time. As a layout entry it is
// declarative, lives in the same shell.json as everything else, and a new
// widget joins the right group by moving one line.
//
// Deliberately quiet. The job is to let the eye find a boundary without adding
// another thing to read — at bar size a full-contrast rule competes with the
// icons it is supposed to be organising.
BarWidget {
  id: root
  moduleName: "separator"

  // Rule thickness along the bar's short axis; the padding either side is what
  // actually does the grouping work, so it is the larger number and the one a
  // caller usually wants to tune.
  readonly property int thickness: Math.max(1, Style.space(1))
  readonly property int pad: setting("pad", Style.bar.groupGap)
  // Short of the full bar height on purpose: a rule that reaches the edges
  // reads as a hard division, which is too strong for a grouping hint.
  readonly property real extent: setting("extent", 0.45)

  // ---- don't separate nothing from something ------------------------------
  //
  // Half this bar's widgets hide themselves when they have nothing to say —
  // OBS when it is not running, Discord when there is no call, the tray with
  // no items, indicators with nothing indicated. A separator whose whole group
  // has vanished is a rule floating against the edge of the cluster with
  // nothing on one side of it, which looks like a rendering bug.
  //
  // So a separator only draws when there is real content on BOTH sides of it.
  // Neighbouring separators do not count as content, which also collapses a
  // run of two rules into nothing when the group between them is empty.
  property bool hasNeighbours: false

  // BarSection's delegate is a Loader, so this widget's parent is that Loader
  // and its parent is the section's RowLayout.
  readonly property Item ownLoader: parent
  readonly property Item section: ownLoader ? ownLoader.parent : null

  function contentBeside() {
    if (!section) return false
    var siblings = section.children
    var index = -1
    for (var i = 0; i < siblings.length; i++)
      if (siblings[i] === ownLoader) { index = i; break }
    if (index < 0) return false

    function solid(loader) {
      if (!loader || loader === ownLoader) return false
      var item = loader.item
      if (!item || !item.visible) return false
      // A separator is not content, and neither is a zero-width widget that is
      // nominally visible (Indicators does exactly that when all three of its
      // indicators are inactive).
      if (item.moduleName === "separator") return false
      return item.implicitWidth > 0
    }

    var before = false
    for (var b = index - 1; b >= 0; b--) if (solid(siblings[b])) { before = true; break }
    var after = false
    for (var a = index + 1; a < siblings.length; a++) if (solid(siblings[a])) { after = true; break }
    return before && after
  }

  // Deferred and coalesced, for the same reason BarWidget defers barX: these
  // signals fire *during* the layout pass, when sibling geometry is still
  // half-settled, and several of them land per change.
  Timer {
    id: settle
    interval: 32
    onTriggered: root.hasNeighbours = root.contentBeside()
  }

  Connections {
    target: root.bar
    enabled: root.bar !== null
    function onLayoutRevisionChanged() { settle.restart() }
  }

  Component.onCompleted: settle.restart()

  visible: hasNeighbours
  implicitWidth: vertical ? barSize : thickness + pad * 2
  implicitHeight: vertical ? thickness + pad * 2 : barSize

  Rectangle {
    anchors.centerIn: parent
    width: root.vertical ? root.barSize * root.extent : root.thickness
    height: root.vertical ? root.thickness : root.barSize * root.extent
    radius: root.thickness / 2
    color: root.bar ? root.bar.barForeground : Color.foreground
    opacity: 0.18
  }
}
