import QtQuick
import Quickshell
import qs.Commons

Label {
  id: root

  property bool loading: false
  property string error: ""
  property real updatedMs: 0
  property real staleAfterMs: 0
  readonly property int msPerMinute: 60 * 1000

  property real nowMs: Date.now()
  readonly property bool hasData: updatedMs > 0
  readonly property bool stale: hasData && staleAfterMs > 0 && nowMs - updatedMs >= staleAfterMs
  readonly property string freshness: !hasData && error !== "" ? "error"
    : !hasData ? "loading"
    : stale || error !== "" ? "stale"
    : "fresh"

  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true) // qmllint disable missing-property

  Timer {
    interval: root.msPerMinute
    repeat: true
    running: root.onScreen && root.hasData && root.staleAfterMs > 0
    onTriggered: root.nowMs = Date.now()
  }
  onUpdatedMsChanged: nowMs = Date.now()

  text: freshness === "loading" ? "--"
    : freshness === "error" ? "x ERR"
    : freshness === "stale" ? " ~" + Util.span((nowMs - updatedMs) / msPerMinute)
    : ""
  color: freshness === "error" ? Colors.urgentText : Colors.textDim
  caption: true
  elide: Text.ElideRight
}
