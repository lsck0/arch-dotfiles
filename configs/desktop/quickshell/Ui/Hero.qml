import QtQuick
import qs.Commons

/**
 * Hero: the one big number per surface, value plus a dim unit on its baseline.
 *
 * Properties:
 *   value  the number, already formatted
 *   unit   trailing unit ("%", "KBPS"), "" hides it
 *   color  number and unit
 *   live   true when the value changes more than once a minute: outline instead of a glow layer
 *   size   font pixel size, Style.font.hero by default (the lock clock doubles it)
 *
 * Usage:
 *   Hero { value: String(root.pct); unit: "%"; color: Util.level(root.pct, [70, 85, 95]) }
 */
Row {
  id: root

  property string value: "--"
  property string unit: ""
  property color color: Color.accent
  property bool live: false
  property int size: Style.font.hero

  spacing: Style.spacing.xs

  Text {
    id: number
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: root.value
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.size
    font.bold: true
    font.letterSpacing: Style.displayTracking
    style: root.live && Style.fx.glow > 0 ? Text.Outline : Text.Normal
    styleColor: Util.alpha(root.color, 0.35)
    layer.enabled: !root.live && Style.fx.glow > 0
    layer.effect: Glow { shadowColor: root.color }
  }

  Text {
    visible: root.unit !== ""
    anchors.baseline: number.baseline
    textFormat: Text.PlainText
    text: root.unit
    color: root.color
    opacity: Style.emphasis.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.capitalization: Font.AllUppercase
  }
}
