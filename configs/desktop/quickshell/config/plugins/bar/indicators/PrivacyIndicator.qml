import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// lit while a stream reads one of its devices, naming the apps that read
BarIndicator {
  id: root

  // xdg-desktop-portal-hyprland names each screencast node so; to Pipewire it is a Video/Source like a camera
  readonly property string screencastPrefix: "xdph-streaming-"

  property string label: ""
  property var devices: []
  property var ignored: function(node) { return false }
  // a screencast node lives exactly as long as its session, so it lights before the reader links
  property bool litByDevice: false

  readonly property var readers: {
    var out = []
    for (let i = 0; i < devices.length; i++) {
      let targets = Audio.targetsOf(devices[i])
      for (let j = 0; j < targets.length; j++)
        if (out.indexOf(targets[j]) < 0 && !ignored(targets[j])) out.push(targets[j])
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
