import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "spacer"

  readonly property int span: Number(setting("size", 12))

  implicitWidth: vertical ? barSize : span
  implicitHeight: vertical ? span : barSize
  visible: span > 0
}
