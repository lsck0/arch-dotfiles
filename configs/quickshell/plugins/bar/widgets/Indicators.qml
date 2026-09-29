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

    // Loader implicit size is read-only, do not assign it
    Loader {
      source: "../indicators/StayAwake.qml"
      onLoaded: if (item) item.bar = root.bar
      visible: item ? item.visible : true
    }

    Loader {
      source: "../indicators/Reminder.qml"
      onLoaded: if (item) item.bar = root.bar
      visible: item ? item.visible : true
    }

    Loader {
      source: "../indicators/Pomodoro.qml"
      onLoaded: if (item) item.bar = root.bar
      visible: item ? item.visible : true
    }
  }
}
