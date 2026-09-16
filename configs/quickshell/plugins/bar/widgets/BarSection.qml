import QtQuick
import QtQuick.Layouts
import qs.Commons
import "BuiltinWidgets.js" as BuiltinWidgets

// Registry-driven bar section (left/center/right). Renders whichever
// widgets `bar.barConfig.layout.<section>` lists, resolving each entry id to
// a .qml URL through the plugin registry (see `widgetUrl` below) — added for
// quickshell Phase 2, replacing the old hardcoded per-section widget list
// in Bar.qml. A Repeater as the root type works as a direct RowLayout
// child: its delegate items become real layout children, same as if they'd
// been written inline.
//
// This is the ONLY resolution path. A parallel `BarWidgetRegistry` used to sit
// alongside it: shell.qml compiled a Component for every enabled bar-widget
// plugin and registered it there, and nothing ever read the result back — the
// Loader below has always gone straight to the URL. That was ~110 lines
// compiling every widget a second time to populate a map with no consumers,
// and three file headers (this one included) describing it as the mechanism.
// Removed 2026-09-16.
Repeater {
  id: root

  required property QtObject bar
  required property string section

  // Through bar.layoutConfig, not bar.barConfig.layout directly: the bar
  // decides which layout this screen gets (full on the main output, a reduced
  // one elsewhere), and reading the raw config here would bypass that.
  // NOTHING BUT `delegate` MAY BE DECLARED AS A CHILD HERE. Repeater's default
  // property is `delegate`, not `data`, so a stray Connections/Timer/QtObject
  // written as a child is silently assigned there and simply never runs — no
  // error, no warning. The manifest-drift check lived here for exactly one
  // edit before that was noticed; it is in Bar.qml now.
  model: bar && bar.layoutConfig && bar.layoutConfig[section]
    ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property var modelData

    readonly property string widgetId: Util.canonicalWidgetId(
      Util.isPlainObject(modelData) ? modelData.id : modelData)

    // Cold-start fallback for the widgets that ship in this directory, used
    // only until the registry's asynchronous scan lands. The map and the
    // manifest-drift check it enforces live in BuiltinWidgets.js — it was a
    // 26-entry object literal rebuilt inside this binding for every widget on
    // every bar, mirroring the manifests with nothing but a comment asking the
    // next person to update both.
    readonly property string builtinFile: BuiltinWidgets.fileFor(widgetId)

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

    // What the widget sees as `settings`: its layout entry, overlaid with the
    // state it saved for itself (shell.qml's widgetSettings — see the trap
    // described there). The layout entry is the declared configuration and the
    // saved state is the widget's own, so the widget's own wins on a clash.
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

    // Reactive, not just set once on load: the settings file is live-watched,
    // so an edit (or another instance of this widget on the other monitor
    // saving state) has to reach an already-loaded widget too.
    onMergedSettingsChanged: if (item && "settings" in item) item.settings = mergedSettings

    onLoaded: {
      if (!item) return
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = widgetLoader.mergedSettings
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
