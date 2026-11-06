import QtQuick
import Quickshell.Io

// A FileView that follows its file: it reloads on every change and re-arms the watch after each load.
FileView {
  watchChanges: true
  printErrors: false
  onFileChanged: reload()
  onLoaded: Util.rearmWatch(this)
}
