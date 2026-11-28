import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// lit while a stream reads one of its devices, naming the apps that read
BarIndicator {
  id: root

  // streams are rejected before their properties are read: the tracker below binds the reader streams, and reading
  // theirs here would loop devices back into readers
  readonly property var videoSources: Audio.nodes.filter(n => !n.isStream
    && (n.type & PwNodeType.VideoSource) === PwNodeType.VideoSource)

  // xdg-desktop-portal-hyprland's screencast node; to Pipewire it is a Video/Source like a camera. Since 1.5 the
  // node is named after the portal and the per-session xdph-streaming-<n> is its media.name
  readonly property string screencastPrefix: "xdph-streaming-"
  readonly property string screencastNode: "xdg-desktop-portal-hyprland"
  function isScreencast(n) {
    return n.name === screencastNode || (n.properties?.["media.name"] ?? "").startsWith(screencastPrefix)
  }

  property string label: ""
  property var devices: []
  // a screencast node lives exactly as long as its session, so it lights before the reader links
  property bool litByDevice: false

  readonly property var readers: {
    var out = []
    for (let i = 0; i < devices.length; i++) {
      let targets = Audio.targetsOf(devices[i])
      for (let j = 0; j < targets.length; j++)
        if (out.indexOf(targets[j]) < 0) out.push(targets[j])
    }
    return out
  }

  readonly property var readerNames: {
    var names = []
    for (let i = 0; i < readers.length; i++) {
      let name = Audio.appName(readers[i])
      if (names.indexOf(name) < 0) names.push(name)
    }
    return names
  }

  active: readers.length > 0 || (litByDevice && devices.length > 0)
  foreground: Colors.semantic.recording
  tooltipText: readerNames.length > 0 ? label + " :: " + readerNames.join(", ") : label

  PwObjectTracker { objects: root.readers }
}
