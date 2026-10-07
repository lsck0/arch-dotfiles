import QtQuick
import qs.Commons

/**
 * KeyHints: the key hint footer, `[ESC] close  [ENTER] run`.
 *
 * Properties:
 *   hints  list of [key, action] pairs, in reading order
 *
 * Usage:
 *   KeyHints { hints: [["ESC", "close"], ["ENTER", "run"]] }
 */
Row {
  id: root

  property var hints: []

  spacing: Style.spacing.md

  Repeater {
    model: root.hints

    Row {
      required property var modelData
      spacing: Style.spacing.xs

      Text {
        textFormat: Text.PlainText
        text: "[" + parent.modelData[0] + "]"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: parent.modelData[1]
        color: Color.foreground
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
