import QtQuick
import Quickshell
import qs.Commons

Text {
  id: root

  property bool loading: false
  property string error: ""
  property bool detailed: false
  property real updatedMs: 0
  property real staleAfterMs: 0
  readonly property int minuteMs: 60000

  property real nowMs: Date.now()
  readonly property bool hasData: updatedMs > 0
  readonly property bool stale: hasData && staleAfterMs > 0 && nowMs - updatedMs >= staleAfterMs
  readonly property string freshness: !hasData && error !== "" ? "error"
    : !hasData ? "loading"
    : stale || error !== "" ? "stale"
    : "fresh"

  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true) // qmllint disable missing-property

  Timer {
    interval: root.minuteMs
    repeat: true
    running: root.onScreen && root.hasData && root.staleAfterMs > 0
    onTriggered: root.nowMs = Date.now()
  }
  onUpdatedMsChanged: nowMs = Date.now()

  textFormat: Text.PlainText
  text: freshness === "loading" ? "--"
    : freshness === "error" ? "x ERR" + (detailed ? " " + error : "")
    : freshness === "stale" ? " ~" + Util.span((nowMs - updatedMs) / minuteMs)
    : ""
  color: freshness === "error" ? Colors.urgent : Colors.foreground
  opacity: freshness === "error" ? Style.emphasis.strong : Style.emphasis.faint
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  elide: Text.ElideRight
}
