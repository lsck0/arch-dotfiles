import QtQuick
import qs.Commons
import qs.Ui

// pending taskwarrior count from TaskState, urgent while any is overdue, gone at zero; a click toggles the tasks
// panel (SUPER+o)
BarWidget {
  id: root
  moduleName: "tasks"

  readonly property bool overdue: TaskState.overdueCount > 0
  readonly property color tint: overdue ? Colors.urgent : (root.bar ? root.bar.barForeground : Colors.foreground)

  visible: TaskState.pendingCount > 0
  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.shape.data
    color: mouseArea.containsMouse || TaskState.panelOpen ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: TaskState.glyph
      color: root.tint
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.overdue ? TaskState.pendingCount + " :: " + TaskState.overdueCount + "!" : String(TaskState.pendingCount)
      color: root.tint
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0 && root.overdue
      layer.effect: Glow { shadowColor: Colors.urgent }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: TaskState.panelOpen = !TaskState.panelOpen
  }
}
