import QtQuick
import QtQuick.Layouts
import qs.Commons

// Registry-driven bar section (left/center/right). Renders whichever
// widgets `bar.barConfig.layout.<section>` lists, resolved against
// `bar.barWidgetRegistry` for the Component to instantiate — added for
// quickshell Phase 2, replacing the old hardcoded per-section widget list
// in Bar.qml. A Repeater as the root type works as a direct RowLayout
// child: its delegate items become real layout children, same as if they'd
// been written inline.
Repeater {
  id: root

  required property QtObject bar
  required property string section

  // Through bar.layoutConfig, not bar.barConfig.layout directly: the bar
  // decides which layout this screen gets (full on the main output, a reduced
  // one elsewhere), and reading the raw config here would bypass that.
  model: bar && bar.layoutConfig && bar.layoutConfig[section]
    ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property var modelData

    readonly property string widgetId: Util.canonicalWidgetId(
      Util.isPlainObject(modelData) ? modelData.id : modelData)

    // Fallback map for the widgets that ship inside this directory, used only
    // until the plugin registry's asynchronous scan lands. The bar must not
    // depend on that scan for its own widgets: a cold boot would otherwise
    // create empty Loaders and never paint a bar at all. Every entry here is
    // also declared in the widget's own `*.manifest.json`, and the manifest is
    // the authority — this is the cold-start mirror of it, so a new first-party
    // widget needs a line in both.
    readonly property string builtinFile: {
      var files = {
        "bar.active-window": "ActiveWindow.qml",
        "bar.agents": "Agents.qml",
        "bar.app-menu": "AppMenu.qml",
        "bar.audio-io": "AudioIO.qml",
        "bar.battery": "Battery.qml",
        "bar.clock": "Clock.qml",
        "bar.costs": "Costs.qml",
        "bar.discord": "Discord.qml",
        "bar.display": "Display.qml",
        "bar.exit": "Exit.qml",
        "bar.indicators": "Indicators.qml",
        "bar.keyboard-layout": "KeyboardLayout.qml",
        "bar.media": "Media.qml",
        "bar.microphone": "Microphone.qml",
        "bar.network": "Network.qml",
        "bar.news": "News.qml",
        "bar.notifications": "Notifications.qml",
        "bar.obs": "Obs.qml",
        "bar.separator": "Separator.qml",
        "bar.spacer": "Spacer.qml",
        "bar.system": "System.qml",
        "bar.system-update": "SystemUpdate.qml",
        "bar.toggles": "Toggles.qml",
        "bar.tray": "Tray.qml",
        "bar.weather": "Weather.qml",
        "bar.workspaces": "Workspaces.qml"
      }
      return files[widgetId] || ""
    }

    readonly property QtObject registry: root.bar && root.bar.shellHost
      ? root.bar.shellHost.pluginRegistry : null

    // Registry first, builtin map second. Going through the registry is what
    // makes a third-party `bar-widget` plugin renderable at all: its .qml
    // lives in the user plugin directory, which this file cannot know about,
    // so a layout entry naming one resolved to "" and drew nothing.
    //
    // `registry.registryRevision` is read for its dependency, not its value:
    // the scan is asynchronous, so this binding must re-run when it completes
    // or a plugin widget would stay on whatever the first pass resolved.
    //
    // Absolute file URLs throughout — Loader's relative URL base is not
    // reliable when this Repeater is synthesized into the shell module at
    // runtime.
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

    // `errorString` is a Component method, not a Loader one. Calling it on
    // the Loader threw "ReferenceError: errorString is not defined" from
    // inside the very handler meant to report the load failure, so a broken
    // widget produced a confusing error about the error reporting instead of
    // naming the widget. `sourceComponent` is the Component the Loader built
    // from `source`, and it is what actually carries the message.
    onStatusChanged: if (status === Loader.Error) {
      var detail = sourceComponent ? sourceComponent.errorString() : "(no detail)"
      console.warn("BarSection[" + root.section + "] failed " + widgetId + ": " + detail)
    }

    // A widget may hide itself when it has nothing to show (battery on an
    // AC-only host, pending-update indicator with no updates, etc.). Loader
    // otherwise keeps the hidden item's implicit width in the RowLayout,
    // producing the large empty gaps seen between tray and battery.
    // Do not bind Loader.visible to item.visible: item.visible inherits the
    // Loader's effective visibility, creating a feedback loop that hid every
    // widget. The Loader stays visible; hidden widgets collapse via Layout.
    visible: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: item && item.visible ? item.implicitWidth : 0
    Layout.maximumWidth: item && item.visible ? item.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: item && item.visible ? item.implicitHeight : 0
    Layout.maximumHeight: item && item.visible ? item.implicitHeight : 0

    onLoaded: {
      if (!item) return
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = Util.isPlainObject(widgetLoader.modelData) ? widgetLoader.modelData : ({})
    }

    // A layout entry naming an id that neither the registry nor the builtin
    // map knows draws nothing at all — that is how `bar.spacer` stayed
    // unreachable without anyone noticing. Warn instead of failing silently.
    //
    // Two entry points because the resolution is asynchronous. At completion
    // an unresolved id is only conclusive once the registry has finished at
    // least one scan (`registryRevision > 0`); before that, a third-party
    // widget is legitimately unresolved for a moment. The change handler
    // covers the later case, where a scan or a config edit takes a widget
    // away again. There is no Timer here on purpose: a Loader's default
    // property is `sourceComponent`, so a Timer declared as its child would
    // be assigned there rather than simply existing alongside it.
    function warnUnresolved() {
      console.warn("BarSection[" + root.section + "]: no widget found for id '"
        + widgetId + "'")
    }
    onWidgetUrlChanged: if (!widgetUrl && widgetId) warnUnresolved()
    Component.onCompleted: if (!widgetUrl && widgetId
      && registry && registry.registryRevision > 0) warnUnresolved()
  }
}
