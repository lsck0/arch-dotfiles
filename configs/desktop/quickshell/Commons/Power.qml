pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// saver from toggle-powermode.sh (forced power-saver, or auto on battery), strips fx and live visuals while on
Singleton {
  id: root

  // volatile toggle state, gone on boot like tlp's forced mode
  readonly property string path:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/toggles/powersaver"

  property bool saver: false

  // the script owns the saver rule; it reloads hyprland and pings back here when saver flips
  readonly property bool onBattery: UPower.onBattery === true
  onOnBatteryChanged: sync()
  Component.onCompleted: sync()

  function sync() { Quickshell.execDetached([Paths.toggle("toggle-powermode.sh"), "sync"]) }

  // the toggle pings over ipc, the file may not exist yet to watch
  function reload() { file.reload() }

  FileView {
    id: file
    path: root.path
    printErrors: false
    onLoaded: root.saver = String(text() || "").trim() === "on"
    onLoadFailed: root.saver = false
  }
}
