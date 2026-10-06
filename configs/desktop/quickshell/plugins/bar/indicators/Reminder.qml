import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  active: TimerState.reminderCount > 0
  activeText: "\u{f088c}"
  inactiveText: "\u{f088c}"
  activeTooltipText: TimerState.reminderTooltip
  inactiveTooltipText: TimerState.reminderTooltip

  onPressed: Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.reminders", "{}"))
}
