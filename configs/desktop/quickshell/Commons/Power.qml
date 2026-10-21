pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
  id: root

  readonly property string path:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/toggles/powersaver"

  property bool saver: false

  readonly property bool onBattery: UPower.onBattery === true
  onOnBatteryChanged: sync()
  Component.onCompleted: sync()

  function sync() { Quickshell.execDetached([Paths.toggle("toggle-powermode.nu"), "sync"]) }

  function reload() { file.reload() }

  FileView {
    id: file
    path: root.path
    printErrors: false
    onLoaded: root.saver = String(text() || "").trim() === "on"
    onLoadFailed: root.saver = false
  }
}
