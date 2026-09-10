import QtQuick
import qs.Commons

// Small-caps-style label that introduces a panel section ("DNS provider",
// "Wi-Fi networks", "Output device", "Paired devices"). Sits between a
// PanelSeparator and the content rows.
Text {
  id: root

  // Accent, not a dimmed foreground. A section header is structure, and
  // structure should be the loudest quiet thing on the panel — the previous
  // Qt.darker(foreground, 1.4) put it *below* the body text it introduces,
  // which is why panels read as an undifferentiated column of rows.
  property color foreground: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption

  // Callers bind `text` from outside this file, so the default has to be set
  // here. AutoText would let a section title that happens to carry a device or
  // network name promote itself to rich text.
  textFormat: Text.PlainText
  color: foreground
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  // Uppercase + wide tracking. With one mono family for everything, letter
  // spacing and case are what separate a section header from body text —
  // there is no second family to switch to. Callers pass ordinary strings
  // and get the treatment automatically, so no call site has to remember to
  // shout.
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Style.headerTracking

  // Glyphs can paint above the box Text reserves for them: JetBrainsMono Nerd
  // Font's outlines run 10% of the em past its own ascent, and a patched or
  // user-chosen family can be worse. That sliver is invisible in normal flow,
  // but a header sitting at the top of a clipping list — bluetooth's device
  // list, network's station list — loses it to the clip and renders beheaded.
  // Reserve the overshoot here so every panel is covered at once.
  topPadding: Math.ceil(fontSize * 0.15)
}
