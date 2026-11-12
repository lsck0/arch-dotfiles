import QtQuick

Item {
  id: root

  property bool blocked: false

  signal moveRequested(int dx, int dy)
  signal closeRequested()
  signal tabRequested(int direction)
  signal pageRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return
    var key = event.key, text = event.text
    if (key === Qt.Key_Escape) closeRequested()
    else if (key === Qt.Key_Tab || key === Qt.Key_Backtab)
      tabRequested((event.modifiers & Qt.ShiftModifier) || key === Qt.Key_Backtab ? -1 : 1)
    else if (key === Qt.Key_PageDown || key === Qt.Key_PageUp) pageRequested(key === Qt.Key_PageDown ? 1 : -1)
    else if (key === Qt.Key_Down || text === "j") moveRequested(0, 1)
    else if (key === Qt.Key_Up || text === "k") moveRequested(0, -1)
    else if (key === Qt.Key_Right || text === "l") moveRequested(1, 0)
    else if (key === Qt.Key_Left || text === "h") moveRequested(-1, 0)
    else {
      if (text && text.length === 1) textKey(text)
      return
    }
    event.accepted = true
  }
}
