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

  PolkitAgent { id: agent }

  // pam_u2f asks for a touch with no response, so the prompt only shows when pam wants one
  Connections {
    target: root.flow
    function onIsResponseRequiredChanged() {
      if (root.flow.isResponseRequired) Qt.callLater(function() { password.text = ""; password.forceActiveFocus() })
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
    hints: [["ENTER", "submit"], ["ESC", "cancel"]]
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

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.flow ? root.flow.message : ""
        color: Colors.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.flow ? root.flow.supplementaryMessage : ""
        color: root.flow && root.flow.supplementaryIsError ? Colors.urgentText : Colors.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      TextField {
        id: password
        Layout.fillWidth: true
        visible: root.flow !== null && root.flow.isResponseRequired
        password: root.flow !== null && !root.flow.responseVisible
        placeholderText: root.flow ? root.flow.inputPrompt : ""
        Keys.onReturnPressed: root.submit()
        Keys.onEnterPressed: root.submit()
        Keys.onEscapePressed: root.cancel()
      }
    }
  }
}
