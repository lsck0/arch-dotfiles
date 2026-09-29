import QtQuick
import QtQuick.Layouts
import qs.Commons
import "BuiltinWidgets.js" as BuiltinWidgets

Repeater {
  id: root

  required property QtObject bar
  required property string section

  // via layoutConfig so secondary screens get their reduced layout
  model: bar && bar.layoutConfig && bar.layoutConfig[section]
    ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property var modelData

    readonly property string widgetId: Util.canonicalWidgetId(
      Util.isPlainObject(modelData) ? modelData.id : modelData)

    // cold-start fallback until the registry scan lands
    readonly property string builtinFile: BuiltinWidgets.fileFor(widgetId)

    readonly property QtObject registry: root.bar && root.bar.shellHost
      ? root.bar.shellHost.pluginRegistry : null

    readonly property string widgetUrl: {
      if (registry && registry.registryRevision >= 0 && registry.installedPlugins) {
        var manifest = registry.installedPlugins[widgetId]
        if (manifest) {
          var fromRegistry = registry.entryPointUrl(manifest, "barWidget")
          if (fromRegistry) return fromRegistry
        }
      }
      if (!builtinFile || !root.bar || !root.bar.shellHost) return ""
      return Util.fileUrl(root.bar.shellHost.shellDir + "/plugins/bar/widgets/" + builtinFile)
    }
    source: widgetUrl

    // errorString is a Component method, not a Loader one
    onStatusChanged: if (status === Loader.Error) {
      var detail = sourceComponent ? sourceComponent.errorString() : "(no detail)"
      console.warn("BarSection[" + root.section + "] failed " + widgetId + ": " + detail)
    }

    // widgets may hide themselves; size follows item.visible
    visible: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: item && item.visible ? item.implicitWidth : 0
    Layout.maximumWidth: item && item.visible ? item.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: item && item.visible ? item.implicitHeight : 0
    Layout.maximumHeight: item && item.visible ? item.implicitHeight : 0

    // layout entry overlaid with saved widget state
    readonly property var mergedSettings: {
      var merged = {}
      if (Util.isPlainObject(modelData))
        for (var k in modelData) merged[k] = modelData[k]
      var host = root.bar ? root.bar.shellHost : null
      if (host && typeof host.settingsForWidget === "function") {
        var saved = host.settingsForWidget(widgetId)
        for (var s in saved) if (s !== "id") merged[s] = saved[s]
      }
      return merged
    }

    // settings file is live-watched, so push updates to loaded items
    onMergedSettingsChanged: if (item && "settings" in item) item.settings = mergedSettings

    onLoaded: {
      if (!item) return
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = widgetLoader.mergedSettings
    }

    // unresolved ids draw nothing, so say so
    function warnUnresolved() {
      console.warn("BarSection[" + root.section + "]: no widget found for id '"
        + widgetId + "'")
    }
    onWidgetUrlChanged: if (!widgetUrl && widgetId) warnUnresolved()
    Component.onCompleted: if (!widgetUrl && widgetId
      && registry && registry.registryRevision > 0) warnUnresolved()
  }
}
