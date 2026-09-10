import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Simplified from upstream's 471-line settings-driven, dynamically-
// reconfigurable indicator cluster (6 possible indicators, hover-reveal
// for inactive ones, per-instance settings UI). This repo only has real
// backing for 3 of them (StayAwake — see toggles/toggle-keep-awake.sh;
// Reminder — see scripts/reminder.sh, added in Phase 6; Pomodoro — see
// scripts/pomodoro.sh, added in roadmap Phase 5. DND moved into the
// notifications widget itself (a Toggle row in its hover panel) rather
// than living here as a separate bar icon — it's a notifications setting,
// so it belongs with the rest of the notifications UI.
// Dictation/NightLight/ScreenRecording still have no backing
// tool/service in this repo at all, per explicit scoping decision — not a
// placeholder gap, a deliberate one). Hardcodes those 3 rather than
// porting the dynamic by-name Loader machinery upstream needs to support
// indicators that don't exist here.
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

    // Loader.implicitWidth/implicitHeight already mirror the loaded item's
    // implicit size automatically (they are read-only — assigning them
    // throws "Invalid property assignment" and fails the whole widget).
    // Only `visible` needs forwarding: GridLayout excludes invisible
    // children from layout, which is what lets a concealed indicator
    // (DND/keep-awake off, or the reminder/pomodoro binary missing) stop
    // reserving its statusSlot width in the bar's right cluster.
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
