import QtQuick
import Quickshell
import qs.Commons

/**
 * DataState: the one marker for data that is not fresh. Never hides its host, it states why:
 *   loading  `--`          no data yet and a fetch is out
 *   error    `x ERR`       the last fetch failed and there is nothing to show; detail after it
 *   stale    ` ~12m`       data older than staleAfterMs, as a suffix next to the value
 *   fresh    nothing, the item collapses to zero width
 * An error with older data still shown reads as stale, the value stays up.
 *
 * Properties:
 *   loading       a fetch is running
 *   error         the last fetch failed ("" means none); shown as its detail when detailed
 *   detailed      append the error text after `x ERR`
 *   updatedMs     epoch ms of the last good data, 0 when none
 *   staleAfterMs  age at which the suffix appears
 *   state         "loading" | "error" | "stale" | "fresh"
 *
 * The age ticks once a minute only while the marker is on screen and stale.
 *
 * Usage:
 *   DataState { loading: proc.running; error: root.errorText; updatedMs: root.updatedMs; staleAfterMs: 90 * 60000 }
 */
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
  readonly property string state: !hasData && error !== "" ? "error"
    : !hasData ? "loading"
    : stale || error !== "" ? "stale"
    : "fresh"

  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true)

  // stale may flip on its own, so the clock runs while there is data that can age
  Timer {
    interval: root.minuteMs
    repeat: true
    running: root.onScreen && root.hasData && root.staleAfterMs > 0
    onTriggered: root.nowMs = Date.now()
  }
  onUpdatedMsChanged: nowMs = Date.now()

  textFormat: Text.PlainText
  text: state === "loading" ? "--"
    : state === "error" ? "x ERR" + (detailed ? " " + error : "")
    : state === "stale" ? " ~" + Util.span((nowMs - updatedMs) / minuteMs)
    : ""
  color: state === "error" ? Color.urgent : Color.foreground
  opacity: state === "error" ? Style.emphasis.strong : Style.emphasis.faint
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  elide: Text.ElideRight
}
