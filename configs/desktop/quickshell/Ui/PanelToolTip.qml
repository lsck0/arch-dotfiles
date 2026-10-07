import QtQuick
import QtQuick.Controls
import qs.Commons

ToolTip {
  id: root

  property color panelForeground: Color.tooltip.text
  property color panelBackground: Color.tooltip.background
  property color panelBorder: Color.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  readonly property var panelBorderSpec: Border.flat(panelBorder, Style.normalBorderWidth)

  delay: 400
  padding: 0

  background: BorderSurface {
    color: root.panelBackground
    borderSpec: root.panelBorderSpec
    radius: Style.shape.surface
  }

  contentItem: Item {
    implicitWidth: tagRow.implicitWidth + tagRow.x + rightPad
    implicitHeight: tagRow.implicitHeight + tagRow.y + botPad

    readonly property real leftPad: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingX
    readonly property real rightPad: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingX
    readonly property real topPad: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingY
    readonly property real botPad: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingY

    Row {
      id: tagRow
      x: parent.leftPad
      y: parent.topPad
      spacing: Style.spacing.xs

      Text {
        anchors.baseline: tipText.baseline
        textFormat: Text.PlainText
        text: ">"
        color: Color.accent
        opacity: Style.emphasis.faint
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
      Text {
        id: tipText
        textFormat: Text.PlainText
        text: root.text
        color: root.panelForeground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }
  }
}
