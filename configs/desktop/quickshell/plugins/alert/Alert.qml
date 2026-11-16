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

  property var alerts: []

  function open(payload) {
    payload = payload || {}
    if (!payload.title && !payload.body) return
    closeTimer.stop()
    root.closing = false

    var next = root.alerts.slice()
    next.push({
      title: String(payload.title || "Reminder"),
      body: String(payload.body || ""),
      glyph: String(payload.glyph || "\u{f0020}"), // md-alarm
      kind: String(payload.kind || ""),
      message: String(payload.message || ""),
      at: Qt.formatTime(new Date(), Util.timeFormat)
    })
    root.alerts = next
  }

  function dismissAt(index) {
    var next = root.alerts.slice()
    next.splice(index, 1)
    root.alerts = next
    if (next.length === 0) close()
  }

  function snoozeAt(index, minutes) {
    var alert = root.alerts[index]
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
    var last = root.alerts.length - 1
    if (last < 0 || root.alerts[last].kind !== "reminder") return false
    root.snoozeAt(last, minutes)
    return true
  }

  function dismissNewest() {
    if (root.alerts.length === 0) return false
    root.dismissAt(root.alerts.length - 1)
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
      root.alerts = []
      root.closing = false
    }
  }

  PanelWindow {
    id: win
    visible: root.alerts.length > 0
    screen: root.mainScreen
    // top centre: the top right corner is the toast column's
    anchors { top: true }
    margins { top: Style.bar.sizeHorizontal + Style.gapsOut } // qmllint disable missing-property
    implicitWidth: Style.space(440)
    implicitHeight: Math.min(stack.implicitHeight, (screen ? screen.height : stack.implicitHeight) - Style.bar.sizeHorizontal - Style.gapsOut * 2) // qmllint disable missing-property
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
      Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: stack.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: stack
          width: flick.width
          spacing: Style.spacing.xs
          opacity: root.closing ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: root.closing ? Style.motion.exit : Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: root.closing ? Style.motion.leave : Style.motion.enter } }

          Repeater {
            model: root.alerts

            delegate: GlassCard {
              id: card
              required property var modelData
              required property int index
              // the keys act on the newest card, so only it shows them
              readonly property bool newest: index === root.alerts.length - 1

              width: stack.width
              readonly property real inset: shape.strokeWidth + Style.surface.padding
              implicitHeight: inner.implicitHeight + inset * 2
              // an alert asks for an answer: its edge is the accent
              strokeColor: Colors.accent

              opacity: 0
              transform: Translate { id: slide; x: Style.space(24) }
              Component.onCompleted: appear.start()
              ParallelAnimation {
                id: appear
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
                NumberAnimation { target: slide; property: "x"; to: 0; duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
              }

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
                  text: card.modelData.kind || "alert"
                  suffix: ":: " + card.modelData.at
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
                      text: card.modelData.glyph
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
                      text: card.modelData.title
                      color: Colors.menu.text
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      wrapMode: Text.WordWrap
                    }
                    Label {
                      width: parent.width
                      visible: card.modelData.body !== ""
                      text: card.modelData.body
                      color: Colors.menu.text
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                Row {
                  anchors.right: parent.right
                  spacing: Style.spacing.xs

                  Repeater {
                    model: card.modelData.kind === "reminder" ? [[root.snoozeShortMin, "5"], [root.snoozeLongMin, "1"]] : []

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
  }
}
