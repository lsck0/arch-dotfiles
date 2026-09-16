import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// New plugin, not from omarchy-shell. A large top-right card that stays up
// until it is dismissed by hand.
//
// This exists because an ordinary notification toast is the wrong shape for
// a timer that has elapsed: toasts auto-expire, so a reminder that fires
// while you are looking at another screen is simply gone. Anything routed
// here is something you asked to be interrupted by — a reminder firing, a
// pomodoro phase ending — so it is deliberately hard to miss and impossible
// to lose. Ordinary confirmations ("reminder set", "pomodoro stopped") stay
// as normal toasts; they are not worth blocking on.
//
// The sound is played by configs/quickshell/scripts/alert.sh, not here, so a reminder is still
// audible when the shell is down. That script also falls back to a plain
// notification if this overlay cannot be summoned.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // A list, not a single alert: two reminders can elapse in the same minute
  // and the second must not silently replace the first.
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
      glyph: String(payload.glyph || "\u{f0020}"),   // md-alarm, cmap-verified
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
    var argv = [Paths.bin("reminder"), String(minutes)]
    if (alert && alert.message) argv.push(alert.message)
    Quickshell.execDetached(argv)
    dismissAt(index)
  }

  function stopPomodoroAt(index) {
    Quickshell.execDetached([Paths.bin("pomodoro"), "stop"])
    dismissAt(index)
  }

  // Same main output as the bar and notifications.
  readonly property var mainScreen: {
    var screens = Quickshell.screens
    var name = root.shell ? root.shell.mainScreenName : ""
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  // close() and dismiss() must stay separate, and only dismiss() may talk to
  // the shell. shell.hide() calls the plugin's own close() — so a close()
  // that calls hide() recurses until the stack blows
  // ("RangeError: Maximum call stack size exceeded"), which then leaves the
  // shell's openPanelIds entry never cleared, so every *later* summon was
  // accepted and silently delivered nothing. Same split ReminderFlow.qml
  // uses, and for the same reason.
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
    // Top-right, per the owner's explicit request. Sized to its content
    // rather than full-screen: a full-screen surface would swallow clicks
    // across the whole desktop for as long as an alert is up, which is the
    // same mistake Bar.qml's removed dismiss-catcher made.
    anchors { top: true; right: true }
    margins { top: Style.bar.sizeHorizontal + Style.spacing.lg; right: Style.spacing.lg }
    implicitWidth: Style.space(440)
    implicitHeight: stack.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "quickshell-alert"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand, not Exclusive: an alert must not steal the keyboard the
    // instant it appears (that would eat keystrokes mid-sentence). Click it
    // and Esc works; ignore it and typing continues uninterrupted.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // Keys must attach to an Item, not to the PanelWindow itself — a
    // PanelWindow is a wayland surface interface, and attaching there logs
    // "Could not attach Keys property to ... is not an Item" and silently
    // never fires. Wrap the content instead.
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

          // Slides in from the right edge it is pinned to.
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
                iconText: "\u{f0156}"          // md-close, cmap-verified
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
        }
      }
    }
    }
  }
}
