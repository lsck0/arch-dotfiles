import QtQuick
import qs.Commons

// centres a glyph on its painted bounds, not the font box
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.iconFamily
  property real fontSize: Style.font.body
  property color color: Color.foreground

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
  readonly property real tightHeight: Math.max(1, glyphMetrics.tightBoundingRect.height)

  // bounding rects are relative to the baseline, not the item top
  readonly property real paintedCenterInItemX:
    glyphMetrics.tightBoundingRect.x + tightWidth / 2 - glyphMetrics.boundingRect.x
  readonly property real paintedCenterInItemY:
    glyphMetrics.tightBoundingRect.y + tightHeight / 2 - glyphMetrics.boundingRect.y

  readonly property real horizontalCorrection: glyph.implicitWidth / 2 - paintedCenterInItemX
  readonly property real verticalCorrection: glyph.implicitHeight / 2 - paintedCenterInItemY

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
    anchors.verticalCenterOffset: root.verticalCorrection
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    renderType: Text.NativeRendering
  }
}
