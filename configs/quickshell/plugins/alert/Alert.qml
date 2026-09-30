import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  // list: two reminders can elapse in the same minute
  property var alerts: []

  property string fontFamily: Style.font.family

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (!payload.title && !payload.body) return

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
    if (next.length === 0) dismiss()
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

  // only dismiss() may talk to the shell; close() is its hide callback
  function close() {
    root.alerts = []
  }

  function dismiss() {
    root.alerts = []
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "panel.alert")
  }

  PanelWindow {
    id: win
    visible: root.alerts.length > 0
    screen: root.mainScreen
    anchors { top: true; right: true }
    margins { top: Style.bar.sizeHorizontal + Style.spacing.lg; right: Style.spacing.lg }
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
      onCloseRequested: root.dismiss()

      Column {
        id: stack
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.alerts

          delegate: BorderSurface {
            id: card
            required property var modelData
            required property int index

            width: stack.width
            implicitHeight: inner.implicitHeight + card.contentTopInset + card.contentBottomInset
            color: Color.menu.background
            borderSpec: Border.flat(Color.accent, Style.selectedBorderWidth > 0 ? Style.selectedBorderWidth : 2)
            radius: Style.cornerRadius
            padding: Style.spacing.panelPadding

            opacity: 0
            transform: Translate { id: slide; x: Style.space(24) }
            Component.onCompleted: appear.start()
            ParallelAnimation {
              id: appear
              NumberAnimation { target: card; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
              NumberAnimation { target: slide; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }

            Column {
              id: inner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: card.contentTopInset
              anchors.leftMargin: card.contentLeftInset
              anchors.rightMargin: card.contentRightInset
              spacing: Style.spacing.lg

              Item {
                width: parent.width
                implicitHeight: alTitleRow.implicitHeight + Style.spacing.xs + alRule.height
                height: implicitHeight

                Row {
                  id: alTitleRow
                  anchors.left: parent.left
                  anchors.top: parent.top
                  spacing: Style.spacing.xs

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: ">"
                    color: Color.accent
                    opacity: Style.emphasis.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: card.modelData.kind ? String(card.modelData.kind).toUpperCase() : "ALERT"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: Style.headerTracking
                    layer.enabled: Style.fx.glow > 0
                    layer.effect: Glow {}
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "_"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    SequentialAnimation on opacity {
                      running: true
                      loops: Animation.Infinite
                      PropertyAnimation { to: 1; duration: 0 }
                      PauseAnimation { duration: 530 }
                      PropertyAnimation { to: 0; duration: 0 }
                      PauseAnimation { duration: 530 }
                    }
                  }
                }

                // decorative, non-interactive
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: alTitleRow.verticalCenter
                  textFormat: Text.PlainText
                  text: "[- o x]"
                  color: Color.accent
                  opacity: Style.emphasis.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: Style.headerTracking
                }

                Rectangle {
                  id: alRule
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: alTitleRow.bottom
                  anchors.topMargin: Style.spacing.xs
                  height: Math.max(1, Style.space(1))
                  color: Util.alpha(Color.accent, 0.8)
                }
              }

              Item {
                width: parent.width
                height: Math.max(badge.height, texts.implicitHeight)

                Rectangle {
                  id: badge
                  width: Style.space(48)
                  height: width
                  radius: width / 2
                  color: Style.selectedFillFor(Color.menu.text, Color.accent)
                  Text {
                    anchors.centerIn: parent
                    text: card.modelData.glyph
                    color: Color.accent
                    font.family: Style.font.iconFamily
                    font.pixelSize: Style.font.heading + Style.space(4)
                    layer.enabled: Style.fx.glow > 0
                    layer.effect: Glow {}
                  }
                }

                Column {
                  id: texts
                  anchors.left: badge.right
                  anchors.leftMargin: Style.spacing.lg
                  anchors.right: closeButton.left
                  anchors.rightMargin: Style.spacing.md
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
                spacing: Style.spacing.sm

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
