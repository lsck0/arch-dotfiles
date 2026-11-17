pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null

  // a model, not an array: an added or dismissed card animates alone, the others shift
  ListModel { id: alerts }

  function open(payload) {
    payload = payload || {}
    if (!payload.title && !payload.body) return
    // an alert during the close replaces the closing card: the model never empties, so the window stays mapped
    var stale = root.closing ? alerts.count : 0
    closeTimer.stop()
    root.closing = false

    alerts.append({
      title: String(payload.title || "Reminder"),
      body: String(payload.body || ""),
      glyph: String(payload.glyph || "\u{f0020}"), // md-alarm
      kind: String(payload.kind || ""),
      message: String(payload.message || ""),
      at: Qt.formatTime(new Date(), Util.timeFormat)
    })
    if (stale > 0) root.removeCards(0, stale)
  }

  // the window keeps its height until removed cards have slid out and the rest moved up
  property real heldHeight: 0
  Timer { id: release; interval: Style.motion.base; onTriggered: root.heldHeight = 0 }

  function removeCards(index, count) {
    root.heldHeight = Math.max(root.heldHeight, stack.contentHeight)
    release.restart()
    alerts.remove(index, count)
  }

  // the last card fades out with the stack, so the window stays until the fade ends
  function dismissAt(index) {
    if (root.closing || index < 0 || index >= alerts.count) return
    if (alerts.count === 1) root.close()
    else root.removeCards(index, 1)
  }

  function snoozeAt(index, minutes) {
    var alert = index >= 0 && index < alerts.count ? alerts.get(index) : null
    var argv = [Paths.script("reminder.nu"), String(minutes)]
    // end of flags: a message such as "--call mom" stays the message
    if (alert && alert.message) argv.push("--", alert.message)
    Quickshell.execDetached(argv)
    dismissAt(index)
  }

  readonly property int snoozeShortMin: 5
  readonly property int snoozeLongMin: 15

  // the keys and IPC act on the newest card, so one Esc after a burst drops one alert, not all of them
  function snoozeNewest(minutes) {
    var last = alerts.count - 1
    if (last < 0 || alerts.get(last).kind !== "reminder") return false
    root.snoozeAt(last, minutes)
    return true
  }

  function dismissNewest() {
    if (alerts.count === 0 || root.closing) return false
    root.dismissAt(alerts.count - 1)
    return true
  }

  IpcHandler {
    target: "alert"
    function dismiss(): string { return root.dismissNewest() ? "ok" : "none" }
    function snooze(minutes: int): string { return root.snoozeNewest(minutes) ? "ok" : "none" }
  }

  readonly property var mainScreen: Util.screenNamed(root.shell ? root.shell.mainScreenName : "") || Quickshell.screens[0] || null

  property bool closing: false

  function close() {
    root.closing = true
    closeTimer.restart()
  }

  Timer {
    id: closeTimer
    interval: Style.motion.exit
    onTriggered: {
      alerts.clear()
      root.closing = false
    }
  }

  PanelWindow {
    id: win
    visible: alerts.count > 0
    screen: root.mainScreen
    // top centre: the top right corner is the toast column's
    anchors { top: true }
    margins { top: Style.bar.sizeHorizontal + Style.gapsOut } // qmllint disable missing-property
    implicitWidth: Style.space(440)
    implicitHeight: Math.min(Math.max(stack.contentHeight, root.heldHeight), (screen ? screen.height : stack.contentHeight) - Style.bar.sizeHorizontal - Style.gapsOut * 2) // qmllint disable missing-property
    color: "transparent"
    WlrLayershell.namespace: "quickshell-alert"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.dismissNewest()
      onTextKey: function(text) {
        if (text === "5") root.snoozeNewest(root.snoozeShortMin)
        else if (text === "1") root.snoozeNewest(root.snoozeLongMin)
      }

      // a burst of alerts (after a suspend) outgrows the screen, so the stack scrolls below the bar
      ListView {
        id: stack
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Style.spacing.xs
        model: alerts
        opacity: root.closing ? 0 : 1
        Behavior on opacity {
          id: stackFade
          NumberAnimation { duration: Style.motion.fadeMs(stackFade.targetValue > 0); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.curve(stackFade.targetValue > 0) }
        }

        // the toasts' transitions: in from the travel distance, out to the edge, the rest shifting at base
        add: Transition {
          NumberAnimation { property: "x"; from: Style.motion.travel; to: 0; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
          NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
        }
        remove: Transition {
          NumberAnimation { property: "x"; to: stack.width; duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave }
          NumberAnimation { property: "opacity"; to: 0; duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave }
        }
        displaced: Transition {
          NumberAnimation { properties: "x,y"; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
          NumberAnimation { property: "opacity"; to: 1; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
        }

        delegate: GlassCard {
          id: card
          required property int index
          required property string title
          required property string body
          required property string glyph
          required property string kind
          required property string at
          // the keys act on the newest card, so only it shows them
          readonly property bool newest: index === alerts.count - 1

          width: stack.width
          readonly property real inset: shape.strokeWidth + Style.surface.padding
          implicitHeight: inner.implicitHeight + inset * 2
          // an alert asks for an answer: its edge is the accent
          strokeColor: Colors.accent

          Column {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: card.inset
            anchors.leftMargin: card.inset
            anchors.rightMargin: card.inset
            spacing: Style.spacing.sm

            HudTitle {
              width: parent.width
              text: card.kind || "alert"
              suffix: ":: " + card.at
              size: Style.font.title
              rule: true
              blinking: win.visible
            }

            Item {
              width: parent.width
              height: Math.max(badge.height, texts.implicitHeight)

              Rectangle {
                id: badge
                width: Style.space(48)
                height: width
                radius: Style.shape.data
                color: Style.selectedFillFor(Colors.menu.text, Colors.accent)
                Label {
                  anchors.centerIn: parent
                  text: card.glyph
                  color: Colors.accentText
                  icon: true
                  font.pixelSize: Style.font.display
                  layer.enabled: Style.fx.glow > 0
                  layer.effect: Glow {}
                }
              }

              Column {
                id: texts
                anchors.left: badge.right
                anchors.leftMargin: Style.spacing.sm
                anchors.right: parent.right
                anchors.verticalCenter: badge.verticalCenter
                spacing: Style.spacing.xxs

                Label {
                  width: parent.width
                  text: card.title
                  color: Colors.menu.text
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Label {
                  width: parent.width
                  visible: card.body !== ""
                  text: card.body
                  color: Colors.menu.text
                  wrapMode: Text.WordWrap
                }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.spacing.xs

              Repeater {
                model: card.kind === "reminder" ? [[root.snoozeShortMin, "5"], [root.snoozeLongMin, "1"]] : []

                Button {
                  required property var modelData
                  variant: "chip"
                  text: (card.newest ? "[" + modelData[1] + "] " : "") + "SNOOZE " + modelData[0] + " MIN"
                  onClicked: root.snoozeAt(card.index, modelData[0])
                }
              }
              Button {
                variant: "chip"
                text: (card.newest ? "[ESC] " : "") + "DISMISS"
                selected: true
                onClicked: root.dismissAt(card.index)
              }
            }
          }
        }
      }
    }
  }
}
