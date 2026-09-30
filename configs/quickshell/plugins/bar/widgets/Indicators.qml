pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Ui

BarWidget {
  id: root
  moduleName: "indicators"

  implicitWidth: vertical ? barSize : row.implicitWidth
  implicitHeight: vertical ? row.implicitHeight : barSize

  GridLayout {
    id: row
    anchors.centerIn: parent
    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    rowSpacing: 0
    columnSpacing: 0

    Repeater {
      model: ["StayAwake.qml", "Reminder.qml", "Pomodoro.qml"]

      // Loader implicit size is read-only, do not assign it
      Loader {
        id: slot
        required property string modelData
        source: "../indicators/" + modelData
        visible: item ? item.visible : true

        // bound, not assigned: these load before BarSection hands this widget its bar
        Binding {
          target: slot.item
          property: "bar"
          value: root.bar
          when: slot.item !== null
        }
      }
    }
  }
}
