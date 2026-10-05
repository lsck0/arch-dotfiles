import QtQuick
import QtQuick.Layouts
import qs.Commons

Repeater {
  id: root

  required property QtObject bar
  required property string section

  // via layoutConfig so secondary screens get their reduced layout
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

    // widgets may hide themselves; size follows item.visible
    visible: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: item && item.visible ? item.implicitWidth : 0
    Layout.maximumWidth: item && item.visible ? item.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: item && item.visible ? item.implicitHeight : 0
    Layout.maximumHeight: item && item.visible ? item.implicitHeight : 0

    // settings file is live-watched, so push updates to loaded items
    readonly property var settings: root.bar && root.bar.shellHost
      ? root.bar.shellHost.settingsForWidget(modelData) : ({})
    onSettingsChanged: if (item && "settings" in item) item.settings = settings

    onLoaded: {
      if (!item) return
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = widgetLoader.settings
    }
  }
}
