import QtQuick
import qs.Commons

Rectangle {
  id: root

  property var borderSpec: Border.none()
  property real padding: 0
  property real topPadding: padding
  property real rightPadding: padding
  property real bottomPadding: padding
  property real leftPadding: padding

  readonly property real borderWidth: Border.width(borderSpec)
  readonly property real contentTopInset: borderWidth + topPadding
  readonly property real contentRightInset: borderWidth + rightPadding
  readonly property real contentBottomInset: borderWidth + bottomPadding
  readonly property real contentLeftInset: borderWidth + leftPadding

  border.color: Border.color(borderSpec)
  border.width: borderWidth
}
