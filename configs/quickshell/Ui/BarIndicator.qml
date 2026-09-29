import QtQuick
import qs.Commons

BarIconButton {
  id: root

  property string activeText: ""
  property string inactiveText: activeText
  property string activeTooltipText: ""
  property string inactiveTooltipText: activeTooltipText

  // inactive indicators hide fully instead of dimming
  opacity: active ? 1 : 0
  visible: !concealed && (text !== "" || keepSpace)
  text: active ? activeText : inactiveText
  tooltipText: active ? activeTooltipText : inactiveTooltipText
  keepSpace: true
  dimmed: !active
  concealed: !active
  interactive: active
  useActiveColor: false
  fontSize: Style.font.caption
  horizontalMargin: 5
  verticalPadding: 5
  fixedWidth: vertical ? -1 : Style.bar.statusSlot
  fixedHeight: vertical ? Style.bar.statusSlot : -1
}
