import QtQuick
import QtQuick.Effects
import qs.Commons

// Small-caps-style label that introduces a panel section ("DNS provider", "Wi-Fi networks", "Output device", "Paired devices").
Text {
  id: root

  // Accent, not a dimmed foreground.
  property color foreground: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption

  // Callers bind `text` from outside this file, so the default has to be set here.
  textFormat: Text.PlainText
  color: foreground
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  // Uppercase + wide tracking.
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Style.headerTracking

  // Glyphs can paint above the box Text reserves for them: JetBrainsMono Nerd Font's outlines run 10% of the em past its own ascent, and a patched or user-chosen family can be worse.
  topPadding: Math.ceil(fontSize * 0.15)

  // Accent neon bloom on the section label.
  layer.enabled: Style.fx.glow > 0
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
