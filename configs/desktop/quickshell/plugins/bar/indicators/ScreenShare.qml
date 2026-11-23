import QtQuick
import qs.Commons

PrivacyIndicator {
  label: "Screen shared"
  text: "\u{f1483}"
  devices: Audio.nodes.filter(n => n.name.startsWith(screencastPrefix))
  litByDevice: true
}
