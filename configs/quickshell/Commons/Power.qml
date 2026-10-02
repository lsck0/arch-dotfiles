pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// tlp power-saver from toggle-powermode.sh, strips fx and live visuals while set
Singleton {
  id: root

  // volatile toggle state, gone on boot like tlp's forced mode
  readonly property string path:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/toggles/powermode"

  property bool saver: false

  // the toggle pings over ipc, the file may not exist yet to watch
  function reload() { file.reload() }

  FileView {
    id: file
    path: root.path
    printErrors: false
    onLoaded: root.saver = String(text() || "").trim() === "power-saver"
    onLoadFailed: root.saver = false
  }
}
