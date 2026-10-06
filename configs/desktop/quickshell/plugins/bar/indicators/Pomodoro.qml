import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  active: TimerState.pomoRunning
  // break phase shows the coffee cup
  activeText: TimerState.pomo.phase === "work" ? "\u{f051f}" : "\u{f0176}"
  inactiveText: "\u{f051f}"
  activeTooltipText: TimerState.pomoTooltip
  inactiveTooltipText: TimerState.pomoTooltip

  onPressed: TimerState.runPomo(["toggle"])
}
