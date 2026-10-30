pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The notes file behind the tasks overlay and the desktop card: one buffer, saved a moment after typing stops. A disk
// change while the buffer has unsaved edits is a conflict, kept unsaved until ctrl+s overwrites the file or ctrl+r
// takes the disk text.
Singleton {
  id: root

  readonly property int saveDelayMs: 600

  property string disk: ""
  property bool loaded: false
  property string text: ""
  property bool edited: false
  // the disk text the buffer was last taken from or saved as
  property string base: ""
  readonly property bool conflict: edited && disk !== base

  function edit(value) {
    if (value === root.text) return
    root.text = value
    root.edited = true
    saveTimer.restart()
  }

  function save() {
    saveTimer.stop()
    if (!root.loaded || !root.edited) return
    if (root.text === root.disk) {
      root.base = root.disk
      root.edited = false
      return
    }
    if (root.conflict) return
    root.write()
  }

  function write() {
    saveTimer.stop()
    root.disk = root.text
    root.base = root.text
    root.edited = false
    file.setText(root.text)
  }

  function takeDisk() {
    saveTimer.stop()
    root.edited = false
    root.base = root.disk
    root.text = root.disk
  }

  function conflictKey(key, modifiers) {
    if (!root.conflict || !(modifiers & Qt.ControlModifier)) return false
    if (key === Qt.Key_S) root.write()
    else if (key === Qt.Key_R) root.takeDisk()
    else return false
    return true
  }

  function loadDisk(value) {
    root.disk = value
    root.loaded = true
    if (!root.edited) root.takeDisk()
  }

  FileView {
    id: file
    path: Paths.notes
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.loadDisk(String(text() || ""))
      Util.rearmWatch(this)
    }
    onLoadFailed: root.loadDisk("")
    onFileChanged: reload()
  }

  Timer {
    id: saveTimer
    interval: root.saveDelayMs
    onTriggered: root.save()
  }
}
