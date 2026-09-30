import QtQuick
import qs.Commons

Text {
  id: root

  property color foreground: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption

  textFormat: Text.PlainText
  color: foreground
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  font.capitalization: Font.AllUppercase
  font.letterSpacing: Style.headerTracking

  // glyphs overshoot the ascent, keep them from clipping
  topPadding: Math.ceil(fontSize * 0.15)
  leftPadding: prefix.implicitWidth

  // every section header carries the prompt marker
  Text {
    id: prefix
    y: root.topPadding
    textFormat: Text.PlainText
    text: "> "
    color: root.color
    font: root.font
  }

  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}
}
