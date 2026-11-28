import QtQuick
import QtQuick.Controls
import qs.Commons

ToolTip {
  id: root

  property color panelForeground: Colors.tooltip.text
  property color panelBackground: Colors.tooltip.background
  property color panelBorder: Colors.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  readonly property var panelBorderSpec: Border.flat(panelBorder, Style.normalBorderWidth)
  // the slide the bar's tooltip enters with; a Popup takes no transform, so background and content share it
  property real slide: 0

  delay: 400
  padding: 0

  enter: Transition {
    NumberAnimation {
      property: "opacity"; from: 0; to: 1
      duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter
    }
    NumberAnimation {
      property: "slide"; from: -Style.motion.travel; to: 0
      duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter
    }
  }
  exit: Transition {
    NumberAnimation {
      property: "opacity"; to: 0
      duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave
    }
    NumberAnimation {
      property: "slide"; to: -Style.motion.travel
      duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave
    }
  }

  background: BorderSurface {
    color: root.panelBackground
    borderSpec: root.panelBorderSpec
    radius: Style.shape.surface
    transform: Translate { y: root.slide }
  }

  contentItem: Item {
    implicitWidth: tagRow.implicitWidth + tagRow.x + padX
    implicitHeight: tagRow.implicitHeight + tagRow.y + padY

    readonly property real padX: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingX
    readonly property real padY: Border.width(root.panelBorderSpec) + Style.spacing.controlPaddingY

    transform: Translate { y: root.slide }

    Row {
      id: tagRow
      x: parent.padX
      y: parent.padY
      spacing: Style.spacing.xs

      Text {
        anchors.baseline: tipText.baseline
        textFormat: Text.PlainText
        text: ">"
        color: Colors.accentText
        opacity: Style.emphasis.faint
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
      Text {
        id: tipText
        // a caller's text can be any length (a device name): capped and wrapped like the bar's tooltip
        width: Math.min(implicitWidth, Style.panelWidth.wide)
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.text
        color: root.panelForeground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }
  }
}
