import QtQuick
import qs.Commons

PrivacyIndicator {
  label: "Microphone"
  text: "\u{f036c}"
  devices: Audio.sources
  // the volume widget's own level meter reads the mic too; a non-stream target is a filter whose readers are not linked here
  ignored: node => !node.isStream || Audio.isPeakMonitor(node)
}
