import QtQuick
import QtQuick.Layouts
import qs.Commons
import "BuiltinWidgets.js" as BuiltinWidgets

// Registry-driven bar section (left/center/right).
Repeater {
  id: root

  required property QtObject bar
  required property string section

  // Through bar.layoutConfig, not bar.barConfig.layout directly: the bar decides which layout this screen gets (full on the main output, a reduced one elsewhere), and reading the raw config here would bypass that.
  model: bar && bar.layoutConfig && bar.layoutConfig[section]
    ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property var modelData

    readonly property string widgetId: Util.canonicalWidgetId(
      Util.isPlainObject(modelData) ? modelData.id : modelData)

    // Cold-start fallback for the widgets that ship in this directory, used only until the registry's asynchronous scan lands.
    readonly property string builtinFile: BuiltinWidgets.fileFor(widgetId)

    readonly property QtObject registry: root.bar && root.bar.shellHost
      ? root.bar.shellHost.pluginRegistry : null

    // Registry first, builtin map second.
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

    // `errorString` is a Component method, not a Loader one.
    onStatusChanged: if (status === Loader.Error) {
      var detail = sourceComponent ? sourceComponent.errorString() : "(no detail)"
      console.warn("BarSection[" + root.section + "] failed " + widgetId + ": " + detail)
    }

    // A widget may hide itself when it has nothing to show (battery on an AC-only host, pending-update indicator with no updates, etc.).
    visible: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: item && item.visible ? item.implicitWidth : 0
    Layout.maximumWidth: item && item.visible ? item.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: item && item.visible ? item.implicitHeight : 0
    Layout.maximumHeight: item && item.visible ? item.implicitHeight : 0

    // What the widget sees as `settings`: its layout entry, overlaid with the state it saved for itself (shell.qml's widgetSettings — see the trap described there).
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

    // Reactive, not just set once on load: the settings file is live-watched, so an edit (or another instance of this widget on the other monitor saving state) has to reach an already-loaded widget too.
    onMergedSettingsChanged: if (item && "settings" in item) item.settings = mergedSettings

    onLoaded: {
      if (!item) return
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = widgetLoader.mergedSettings
    }

    // A layout entry naming an id that neither the registry nor the builtin map knows draws nothing at all — that is how `bar.spacer` stayed unreachable without anyone noticing.
    function warnUnresolved() {
      console.warn("BarSection[" + root.section + "]: no widget found for id '"
        + widgetId + "'")
    }
    onWidgetUrlChanged: if (!widgetUrl && widgetId) warnUnresolved()
    Component.onCompleted: if (!widgetUrl && widgetId
      && registry && registry.registryRevision > 0) warnUnresolved()
  }
}
