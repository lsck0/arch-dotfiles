pragma ComponentBehavior: Bound
import QtQuick

// a list masked by its ListFade while it overflows
ListView {
  id: fadedList
  required property ListFade fade

  layer.enabled: fade.overflows
  layer.effect: FadeMask { maskSource: fadedList.fade }
}
