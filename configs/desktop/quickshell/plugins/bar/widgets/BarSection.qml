pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Repeater {
  id: root

  // untyped: Bar.qml instantiates this file, so it cannot import Bar back
  required property var bar
  required property string section

  model: bar && bar.layoutConfig ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property string modelData

    source: Util.fileUrl(Paths.barWidget(modelData + ".qml"))

    // errorString is a Component method, not a Loader one
    onStatusChanged: if (status === Loader.Error) {
      var detail = sourceComponent ? sourceComponent.errorString() : "(no detail)"
      console.warn("BarSection[" + root.section + "] failed " + modelData + ": " + detail)
    }

    // duck-typed: bar and settings exist only where a widget declares them
    readonly property var widget: item

    // widgets may hide themselves; size follows widget.visible
    visible: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: widget && widget.visible ? widget.implicitWidth : 0
    Layout.maximumWidth: widget && widget.visible ? widget.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: widget && widget.visible ? widget.implicitHeight : 0
    Layout.maximumHeight: widget && widget.visible ? widget.implicitHeight : 0

    readonly property var settings: root.bar && root.bar.shellHost
      ? root.bar.shellHost.settingsForWidget(modelData) : ({})
    onSettingsChanged: if (widget && "settings" in widget) widget.settings = settings

    onLoaded: {
      if (!widget) return
      if ("bar" in widget) widget.bar = root.bar
      if ("settings" in widget) widget.settings = widgetLoader.settings
    }
  }
}
