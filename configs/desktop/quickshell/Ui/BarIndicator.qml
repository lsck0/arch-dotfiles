import QtQuick
import qs.Commons

BarIconButton {
  id: root

  property string activeText: ""
  property string activeTooltipText: ""
  property string inactiveTooltipText: activeTooltipText

  opacity: active ? 1 : 0
  visible: !concealed && (text !== "" || keepSpace)
  text: activeText
  tooltipText: active ? activeTooltipText : inactiveTooltipText
  keepSpace: true
  dimmed: !active
  concealed: !active
  interactive: active
  useActiveColor: false
  fontSize: Style.font.caption
  hoverFill: true
  fixedWidth: Style.bar.statusSlot
}
