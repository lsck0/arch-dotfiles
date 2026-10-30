pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Item {
  id: root

  property string text: ""
  property string suffix: ""
  property bool rule: false
  property bool blinking: true
  property color color: Colors.accentText
  property int size: Style.font.caption
  property int typed: -1

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
      text: "> " + (root.typed < 0 ? root.text : root.text.substring(0, root.typed))
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow {}
    }
    Part { visible: root.suffix !== ""; text: root.suffix; color: Colors.textDim }
    BlinkCaret { anchors.verticalCenter: parent.verticalCenter; color: root.color; size: root.size; running: root.blinking }
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
