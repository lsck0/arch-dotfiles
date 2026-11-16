pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property int selectedIndex: 0

  signal canceled()
  signal confirmed()

  function handleKey(event) {
    if (!root.opened) return false

    if (event.key === Qt.Key_Escape) {
      root.canceled()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.selectedIndex === 0) root.canceled()
      else root.confirmed()
      return true
    } else if (event.key === Qt.Key_Y) {
      root.confirmed()
      return true
    } else if (event.key === Qt.Key_N) {
      root.canceled()
      return true
    }

    return false
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: Colors.menu.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    GlassCard {
      id: card
      readonly property real inset: shape.strokeWidth + Style.spacing.lg
      width: Math.min(parent.width - Style.space(32), Style.space(370))
      height: card.inset * 2 + messageText.implicitHeight + Style.space(20) + Style.space(34)
      anchors.centerIn: parent
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      transformOrigin: Item.Center
      Behavior on opacity { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
      Behavior on scale { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.margins: card.inset

        Label {
          id: prompt
          anchors.left: parent.left
          anchors.top: parent.top
          text: ">"
          color: Colors.textFor(Colors.accent)
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.title
        }

        Label {
          id: messageText
          anchors.left: prompt.right
          anchors.leftMargin: Style.spacing.xs
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.md

          Repeater {
            model: [root.cancelText, root.confirmText]

            BorderSurface {
              id: choice
              required property int index
              required property string modelData

              readonly property bool selected: root.selectedIndex === index
              readonly property bool destructive: index === 1

              width: Style.space(104)
              height: Style.space(34)
              color: selected
                ? (destructive ? Util.alpha(Colors.urgent, 0.22) : Colors.menu.selectedBackground)
                : "transparent"
              borderSpec: Border.flat(destructive
                ? (selected ? Colors.urgent : Util.alpha(Colors.urgent, 0.56))
                : (selected ? Colors.accent : Util.alpha(Colors.menu.text, 0.38)), Style.normalBorderWidth)
              radius: 0

              Label {
                anchors.centerIn: parent
                text: "[ " + choice.modelData + " ]"
                color: choice.selected ? Colors.menu.selectedText : Colors.menu.text
                caption: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.labelTracking
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = choice.index
                onClicked: {
                  if (choice.index === 0) root.canceled()
                  else root.confirmed()
                }
              }
            }
          }
        }
      }
    }
  }
}
