import QtQuick
import qs.Commons

WidgetButton {
  id: root

  property real slotSize: Style.bar.iconSlot
  property real opticalSize: Style.bar.iconCanvas

  fontFamily: Style.font.iconFamily

  labelVisible: false
  hasVisualContent: text !== ""
  fontSize: Style.bar.iconFont
  fixedWidth: slotSize

  Item {
    anchors.centerIn: parent
    width: root.opticalSize
    height: root.opticalSize

    OpticalGlyph {
      anchors.fill: parent
      text: root.text
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      color: root.active && root.useActiveColor ? root.activeColor : root.foreground

      layer.enabled: Style.fx.glow > 0 && root.active
      layer.effect: Glow {}
    }
  }
}
