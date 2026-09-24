import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Simplified from upstream's 471-line settings-driven, dynamically- reconfigurable indicator cluster (6 possible indicators, hover-reveal for inactive ones, per-instance settings UI).
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

    // Loader.implicitWidth/implicitHeight already mirror the loaded item's implicit size automatically (they are read-only — assigning them throws "Invalid property assignment" and fails the whole widget).
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
