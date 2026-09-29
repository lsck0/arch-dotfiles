import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// divider between groups of bar widgets
BarWidget {
  id: root
  moduleName: "separator"

  readonly property int thickness: Math.max(1, Style.space(1))
  readonly property int pad: setting("pad", Style.bar.groupGap)

  // hide unless there is visible content on both sides
  property bool hasNeighbours: false

  // parent is the BarSection Loader, its parent the RowLayout
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
      // separators and zero-width widgets are not content
      if (item.moduleName === "separator") return false
      return item.implicitWidth > 0
    }

    var before = false
    for (var b = index - 1; b >= 0; b--) if (solid(siblings[b])) { before = true; break }
    var after = false
    for (var a = index + 1; a < siblings.length; a++) if (solid(siblings[a])) { after = true; break }
    return before && after
  }

  // deferred: layout signals fire before sibling geometry settles
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

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.vertical ? "⋮" : "::"
    color: Color.accent
    opacity: 0.5
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.letterSpacing: Style.headerTracking
    layer.enabled: Style.fx.glow > 0
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Style.fx.glowColor
      shadowBlur: 1.0
      shadowVerticalOffset: 0
      shadowHorizontalOffset: 0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
  }
}
