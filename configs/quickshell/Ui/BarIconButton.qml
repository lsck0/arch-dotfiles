import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

// Verbatim from omarchy-shell: an icon-only WidgetButton, using OpticalGlyph for a properly-centered icon-font glyph instead of a plain Text baseline.
WidgetButton {
  id: root

  property Component iconComponent: null
  property real slotSize: Style.bar.iconSlot
  property real opticalSize: Style.bar.iconCanvas

  // Icon-only by construction (labelVisible below is hard-false), so it must draw from the pinned icon family rather than WidgetButton's default of bar.fontFamily.
  fontFamily: bar ? bar.iconFontFamily : Style.font.iconFamily

  labelVisible: false
  hasVisualContent: text !== "" || iconComponent !== null
  fontSize: Style.bar.iconFont
  fixedWidth: vertical ? -1 : slotSize
  fixedHeight: vertical ? slotSize : -1

  Item {
    id: opticalCanvas
    anchors.centerIn: parent
    width: root.opticalSize
    height: root.opticalSize

    OpticalGlyph {
      id: glyph
      anchors.fill: parent
      visible: root.iconComponent === null
      text: root.text
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      color: root.active && root.useActiveColor ? root.activeColor : root.foreground
      rotation: root.textRotation

      // Accent neon bloom on the active glyph.
      layer.enabled: Style.fx.glow > 0 && root.active
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Style.fx.glowColor
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
    }

    Loader {
      anchors.fill: parent
      visible: root.iconComponent !== null
      sourceComponent: root.iconComponent
    }
  }
}
