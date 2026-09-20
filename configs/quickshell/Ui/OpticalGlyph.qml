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
  readonly property real tightHeight: Math.max(1, glyphMetrics.tightBoundingRect.height)

  // Both bounding rects are relative to the text's ORIGIN (the baseline), not
  // to the Text item's top-left: at 24px this font reports boundingRect.y as
  // -27.1 against an implicitHeight of 38. Subtracting boundingRect turns a
  // metric coordinate into an item coordinate, which is what implicitWidth /
  // implicitHeight are in. Without that subtraction a "correction" comes out
  // tens of pixels wrong and throws the glyph clean out of its box —
  // horizontally it happened to work only because boundingRect.x is 0 here.
  readonly property real paintedCenterInItemX:
    glyphMetrics.tightBoundingRect.x + tightWidth / 2 - glyphMetrics.boundingRect.x
  readonly property real paintedCenterInItemY:
    glyphMetrics.tightBoundingRect.y + tightHeight / 2 - glyphMetrics.boundingRect.y

  readonly property real horizontalCorrection: glyph.implicitWidth / 2 - paintedCenterInItemX
  // The vertical half of the same correction, which was missing. It is
  // sub-pixel for this font (±0.45px), but NativeRendering snaps to whole
  // device pixels, so which side of a pixel boundary the glyph lands on is
  // exactly what decides whether a badge looks centred.
  readonly property real verticalCorrection: glyph.implicitHeight / 2 - paintedCenterInItemY

  readonly property real paintedCenterX: glyph.x + paintedCenterInItemX
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
    anchors.verticalCenterOffset: root.verticalCorrection
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    renderType: Text.NativeRendering
  }
}
