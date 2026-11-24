import QtQuick
import qs.Commons

// a status glyph in the bar's indicator slot, shown only while its state is active
BarIconButton {
  visible: active
  concealed: !active
  useActiveColor: false
  fontSize: Style.font.caption
  hoverFill: true
  fixedWidth: Style.bar.statusSlot
}
