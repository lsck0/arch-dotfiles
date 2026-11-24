pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Polkit
import qs.Commons
import qs.Ui

// The session's polkit agent: a window agent sits under every layer surface, so its prompt hid behind open panels.
Item {
  id: root

  property var shell: null

  readonly property var flow: agent.flow // qmllint disable unresolved-type
  readonly property bool opened: agent.isActive && flow !== null
  // false while pam waits on a key touch or a finger: nothing to type, nothing to submit
  readonly property bool responseRequired: flow !== null && flow.isResponseRequired

  PolkitAgent { id: agent }

  // pam_u2f asks for a touch with no response, so the prompt only shows when pam wants one
  Connections {
    target: root.flow
    function onIsResponseRequiredChanged() {
      if (root.flow.isResponseRequired) Qt.callLater(function() { password.text = ""; password.forceActiveFocus() })
    }
    function onFailedChanged() {
      if (root.flow.failed) authShake.play()
    }
  }

  function submit() {
    if (!root.flow || !root.flow.isResponseRequired) return
    root.flow.submit(password.text)
    password.text = ""
  }

  function cancel() {
    if (root.flow) root.flow.cancelAuthenticationRequest()
  }

  OverlayCard {
    open: root.opened
    name: "polkit"
    title: "authenticate"
    suffix: root.flow ? root.flow.actionId : ""
    hints: (root.responseRequired ? [["ENTER", "submit"]] : []).concat([["ESC", "cancel"]])
    scanlines: false
    cardWidth: Style.space(480)
    cardHeight: authBody.implicitHeight + chromeHeight
    onDismissed: root.cancel()

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.cancel()
    }

    ColumnLayout {
      id: authBody
      width: parent.width
      spacing: Style.spacing.md
      transform: Shake { id: authShake }

      Label {
        Layout.fillWidth: true
        text: root.flow ? root.flow.message : ""
        color: Colors.menu.text
        wrapMode: Text.WordWrap
      }

      Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.flow ? root.flow.supplementaryMessage || (root.flow.failed ? "> AUTHENTICATION FAILED"
          : !root.responseRequired ? "> WAITING FOR TOUCH" : "") : ""
        color: root.flow && (root.flow.supplementaryIsError || root.flow.failed) ? Colors.urgentText : Colors.textDim
        caption: true
        wrapMode: Text.WordWrap
      }

      TextField {
        id: password
        Layout.fillWidth: true
        visible: root.responseRequired
        password: root.flow !== null && !root.flow.responseVisible
        placeholderText: root.flow ? root.flow.inputPrompt : ""
        Keys.onReturnPressed: root.submit()
        Keys.onEnterPressed: root.submit()
        Keys.onEscapePressed: root.cancel()
      }
    }
  }
}
