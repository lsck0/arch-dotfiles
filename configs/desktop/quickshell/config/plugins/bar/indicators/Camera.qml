import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons

PrivacyIndicator {
  label: "Camera"
  text: "\u{f05a0}"
  devices: Audio.nodes.filter(n => !n.isStream && (n.type & PwNodeType.VideoSource) === PwNodeType.VideoSource
    && !isScreencast(n))
}
