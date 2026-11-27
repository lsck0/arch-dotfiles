import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons

PrivacyIndicator {
  label: "Screen shared"
  text: "\u{f1483}"
  devices: Audio.nodes.filter(n => !n.isStream && (n.type & PwNodeType.VideoSource) === PwNodeType.VideoSource
    && isScreencast(n))
  litByDevice: true
}
