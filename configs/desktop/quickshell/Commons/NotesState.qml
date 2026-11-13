pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The notes file behind the tasks overlay and the desktop card: one buffer, saved a moment after typing stops. A disk
// change while the buffer has unsaved edits is a conflict, kept unsaved until ctrl+s overwrites the file or ctrl+r
// takes the disk text. A conflict still open when the editor lets go (flush) goes to a dated copy beside the file.
Singleton {
  id: root

  readonly property int saveDelayMs: 600
  readonly property string glyph: "\u{f0f6}" // fa-file-text-o, as capture.nu's notes

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

  // the panel closing or the shell going away: a conflicting buffer is kept as a copy, the disk text taken
  function flush() {
    root.save()
    if (!root.conflict) return
    var copy = Paths.notes.replace(/\.md$/, "") + ".conflict-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".md"
    aside.path = copy
    aside.setText(root.text)
    root.takeDisk()
    Quickshell.execDetached(["notify-send", "-a", "quickshell-action", "-u", "low", "-h", "string:lsck0-glyph:" + root.glyph,
      "--", "Notes changed on disk", "your edits are in " + copy.replace(Paths.home, "~")])
  }

  Component.onDestruction: root.flush()

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

  // an editor bound to the buffer takes a change made elsewhere, keeping its cursor
  function syncInto(editor) {
    if (editor.text === root.text) return
    var cursor = editor.cursorPosition
    editor.text = root.text
    editor.cursorPosition = Math.min(cursor, editor.length)
  }

  function loadDisk(value) {
    root.disk = value
    root.loaded = true
    if (!root.edited) root.takeDisk()
  }

  WatchedFile {
    id: file
    path: Paths.notes
    onLoaded: root.loadDisk(String(text() || ""))
    onLoadFailed: root.loadDisk("")
  }

  FileView {
    id: aside
    preload: false
    blockWrites: true
    printErrors: false
  }

  Timer {
    id: saveTimer
    interval: root.saveDelayMs
    onTriggered: root.save()
  }
}
