pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "indicators"
  barPriority: 60

  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  Row {
    id: row
    anchors.centerIn: parent

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
