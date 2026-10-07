import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null

  // list: two reminders can elapse in the same minute
  property var alerts: []

  property string fontFamily: Style.font.family

  function open(payload) {
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
      at: Qt.formatTime(new Date(), "HH:mm")
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
    var argv = [Paths.script("reminder.sh"), String(minutes)]
    if (alert && alert.message) argv.push(alert.message)
    Quickshell.execDetached(argv)
    dismissAt(index)
  }

  function stopPomodoroAt(index) {
    Quickshell.execDetached([Paths.script("pomodoro.sh"), "stop"])
    dismissAt(index)
  }

  // same output as the bar
  readonly property var mainScreen: {
    var screens = Quickshell.screens
    var name = root.shell ? root.shell.mainScreenName : ""
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  // the stack fades out before the list empties
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
    anchors { top: true; right: true }
    margins { top: Style.bar.sizeHorizontal + Style.spacing.sm; right: Style.spacing.sm }
    implicitWidth: Style.space(440)
    implicitHeight: stack.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "quickshell-alert"
    WlrLayershell.layer: WlrLayer.Overlay
    // ondemand: an alert must not steal keystrokes
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // keys cannot attach to a PanelWindow
    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: stack
        width: parent.width
        spacing: Style.spacing.xs
        opacity: root.closing ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.closing ? Style.motion.exit : Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: root.closing ? Style.motion.leave : Style.motion.enter } }

        Repeater {
          model: root.alerts

          delegate: BorderSurface {
            id: card
            required property var modelData
            required property int index

            width: stack.width
            implicitHeight: inner.implicitHeight + card.contentTopInset + card.contentBottomInset
            color: Color.menu.background
            borderSpec: Border.flat(Color.accent, Style.selectedBorderWidth)
            radius: Style.shape.surface
            padding: Style.surface.padding

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
              anchors.topMargin: card.contentTopInset
              anchors.leftMargin: card.contentLeftInset
              anchors.rightMargin: card.contentRightInset
              spacing: Style.spacing.sm

              HudTitle {
                width: parent.width
                text: card.modelData.kind || "alert"
                decor: true
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
                  color: Style.selectedFillFor(Color.menu.text, Color.accent)
                  Text {
                    anchors.centerIn: parent
                    text: card.modelData.glyph
                    color: Color.accent
                    font.family: Style.font.iconFamily
                    font.pixelSize: Style.font.display
                    layer.enabled: Style.fx.glow > 0
                    layer.effect: Glow {}
                  }
                }

                Column {
                  id: texts
                  anchors.left: badge.right
                  anchors.leftMargin: Style.spacing.sm
                  anchors.right: closeButton.left
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: badge.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: card.modelData.title
                    color: Color.menu.text
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    visible: card.modelData.body !== ""
                    textFormat: Text.PlainText
                    text: card.modelData.body
                    color: Color.menu.text
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: card.modelData.at
                    color: Color.menu.text
                    opacity: Style.emphasis.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelActionButton {
                  id: closeButton
                  anchors.right: parent.right
                  anchors.top: parent.top
                  iconText: "\u{f0156}" // md-close
                  tooltipText: "Dismiss"
                  foreground: Color.menu.text
                  onClicked: root.dismissAt(card.index)
                }
              }

              Row {
                anchors.right: parent.right
                spacing: Style.spacing.xs

                Chip {
                  visible: card.modelData.kind === "reminder"
                  text: "Snooze 5 min"
                  onClicked: root.snoozeAt(card.index, 5)
                }
                Chip {
                  visible: card.modelData.kind === "reminder"
                  text: "Snooze 15 min"
                  onClicked: root.snoozeAt(card.index, 15)
                }
                Chip {
                  visible: card.modelData.kind === "pomodoro"
                  text: "Stop pomodoro"
                  onClicked: root.stopPomodoroAt(card.index)
                }
                Chip {
                  text: "Dismiss"
                  selected: true
                  onClicked: root.dismissAt(card.index)
                }
              }
            }

            HudFrame {}
            Scanlines {}
          }
        }
      }
    }
  }
}
