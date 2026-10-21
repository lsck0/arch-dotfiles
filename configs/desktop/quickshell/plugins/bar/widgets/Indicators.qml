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
      model: ["StayAwake.qml"]

      Loader {
        id: slot
        required property string modelData
        source: "../indicators/" + modelData
        visible: item ? !(item as BarIndicator).concealed : true

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
