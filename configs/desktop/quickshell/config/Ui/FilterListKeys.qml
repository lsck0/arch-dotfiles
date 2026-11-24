import QtQuick
import qs.Commons

// the keys an overlay list with a typed filter shares: cursor steps and jumps, ENTER, and editing the filter. handle()
// returns false for any other key, so the plugin checks its own keys first.
QtObject {
  id: root

  required property ListCursor cursor
  property int index: 0
  property string filter: ""

  signal escaped()
  signal stepped(int delta)
  signal jumped(int index)
  signal activated(int modifiers)
  signal filterCleared()
  signal filterEdited(string text)

  function handle(event) {
    var key = event.key, modifiers = event.modifiers
    if (key === Qt.Key_Escape) root.escaped()
    else if (key === Qt.Key_Up || Util.isPrev(key, modifiers)) root.stepped(-1)
    else if (key === Qt.Key_Down || Util.isNext(key, modifiers)) root.stepped(1)
    else if ((modifiers & Qt.ControlModifier) && key === Qt.Key_U) root.filterCleared()
    else if (key === Qt.Key_PageUp) root.jumped(root.cursor.page(root.index, -1))
    else if (key === Qt.Key_PageDown) root.jumped(root.cursor.page(root.index, 1))
    else if (key === Qt.Key_Home) root.jumped(0)
    else if (key === Qt.Key_End) root.jumped(root.cursor.list.count - 1)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.activated(modifiers)
    else if (Util.isWordDelete(key, modifiers)) root.filterEdited(Util.wordDelete(root.filter))
    else if (key === Qt.Key_Backspace) root.filterEdited(root.filter.slice(0, -1))
    else if (Util.printable(event.text)) root.filterEdited(root.filter + event.text)
    else return false
    return true
  }
}
