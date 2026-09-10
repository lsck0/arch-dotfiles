import QtQuick
import qs.Commons

// Verbatim from omarchy-shell: centers a glyph on its painted (not font-box)
// bounds so icon fonts don't look vertically/horizontally off-center.
Item {
  id: root

  property string text: ""
  // Icon family by default: OpticalGlyph exists solely to draw an
  // icon-font glyph properly centred. A caller may still override.
  property string fontFamily: Style.font.iconFamily
  property real fontSize: Style.font.body
  property color color: Color.foreground
  property bool debugBounds: false

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
  readonly property real horizontalCorrection: glyph.implicitWidth / 2 - (glyphMetrics.tightBoundingRect.x + tightWidth / 2)
  readonly property real paintedCenterX: glyph.x + glyphMetrics.tightBoundingRect.x + tightWidth / 2
  readonly property real baselineY: glyph.y + glyph.baselineOffset

  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }

  Text {
    id: glyph
    textFormat: Text.PlainText
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.horizontalCorrection
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    renderType: Text.NativeRendering
  }
}
