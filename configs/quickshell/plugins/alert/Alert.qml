import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// New plugin, not from omarchy-shell. A large top-left card that stays up
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
// The sound is played by scripts/alert.sh, not here, so a reminder is still
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
    // Top-left, per the owner's explicit request. Sized to its content
    // rather than full-screen: a full-screen surface would swallow clicks
    // across the whole desktop for as long as an alert is up, which is the
    // same mistake Bar.qml's removed dismiss-catcher made.
    anchors { top: true; left: true }
    margins { top: Style.bar.sizeHorizontal + Style.spacing.lg; left: Style.spacing.lg }
    implicitWidth: Style.space(560)
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
          implicitHeight: Math.max(Style.space(120), inner.implicitHeight + Style.spacing.panelPadding * 2)
          color: Color.menu.background
          borderSpec: Border.flat(Color.accent, Style.selectedBorderWidth > 0 ? Style.selectedBorderWidth : 2)
          radius: Style.cornerRadius
          padding: Style.spacing.panelPadding

          Row {
            id: inner
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.lg

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: card.modelData.glyph
              color: Color.accent
              font.family: Style.font.iconFamily
              // Oversized on purpose: this is meant to be readable from
              // across the room, not scanned like a toast.
              font.pixelSize: Style.space(46)
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(150)
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                text: card.modelData.title
                color: Color.menu.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                visible: card.modelData.body !== ""
                text: card.modelData.body
                color: Color.menu.text
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
              }
              Text {
                text: card.modelData.at
                color: Color.menu.text
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{f0156}"          // md-close, cmap-verified
              tooltipText: "Dismiss"
              foreground: Color.menu.text
              fontFamily: root.fontFamily
              size: Style.space(32)
              onClicked: root.dismissAt(card.index)
            }
          }

          // Clicking anywhere on the card dismisses it too — the close
          // button is for discoverability, not the only target.
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismissAt(card.index)
            // Let the action button win where they overlap.
            z: -1
          }
        }
      }
    }
    }
  }
}
