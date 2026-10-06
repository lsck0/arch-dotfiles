import QtQuick
import qs.Commons

/**
 * HudTitle: the "> TITLE _ suffix ... [- o x]" header over every panel, overlay and splash, with its accent rule.
 *
 * Without a width it is as wide as its row, so it centres like a Text; give it a width for decor to sit at the right edge.
 *
 * Properties:
 *   text      title, drawn uppercase
 *   suffix    faint text after the caret, "" hides it; counts are spelled "[" + n + "]"
 *   decor     Style.decor at the right edge
 *   rule      accent rule under the row, counted in implicitHeight
 *   blinking  caret blinks while true (bind to the owner's open state)
 *   color     prompt, title and caret
 *   size      font pixel size of the row
 *
 * Usage:
 *   HudTitle { width: parent.width; text: "session"; suffix: "@" + root.userName; decor: true; rule: true; blinking: root.opened }
 */
Item {
  id: root

  property string text: ""
  property string suffix: ""
  property bool decor: false
  property bool rule: false
  property bool blinking: true
  property color color: Color.accent
  property int size: Style.font.caption

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight + (rule ? Style.spacing.xxs + ruleLine.height : 0)

  component Part: Text {
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.size
  }

  Row {
    id: row
    spacing: Style.spacing.xs

    Part {
      text: "> " + root.text
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow {}
    }
    BlinkCaret { anchors.verticalCenter: parent.verticalCenter; color: root.color; size: root.size; running: root.blinking }
    Part { visible: root.suffix !== ""; text: root.suffix; color: Color.menu.text; opacity: Style.emphasis.faint }
  }

  Part {
    visible: root.decor
    anchors.verticalCenter: row.verticalCenter
    anchors.right: parent.right
    text: Style.decor
    opacity: Style.emphasis.faint
    font.pixelSize: Style.font.caption
    font.letterSpacing: Style.headerTracking
  }

  Rectangle {
    id: ruleLine
    visible: root.rule
    anchors.top: row.bottom
    anchors.topMargin: Style.spacing.xxs
    width: parent.width
    height: Math.max(1, Style.space(1))
    color: Util.alpha(root.color, 0.8)
  }
}
