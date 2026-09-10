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
    // Resolve first-party widgets directly. The plugin registry is useful for
    // discovery/settings, but the bar must not depend on its asynchronous scan:
    // a cold boot can otherwise create an empty Loader and never paint content.
    readonly property string widgetSource: {
      var files = {
        "bar.active-window": "ActiveWindow.qml",
        "bar.agents": "Agents.qml",
        "bar.app-menu": "AppMenu.qml",
        "bar.audio-io": "AudioIO.qml",
        "bar.battery": "Battery.qml",
        "bar.clock": "Clock.qml",
        "bar.costs": "Costs.qml",
        "bar.display": "Display.qml",
        "bar.indicators": "Indicators.qml",
        "bar.keyboard-layout": "KeyboardLayout.qml",
        "bar.media": "Media.qml",
        "bar.microphone": "Microphone.qml",
        "bar.network": "Network.qml",
        "bar.news": "News.qml",
        "bar.notifications": "Notifications.qml",
        "bar.system": "System.qml",
        "bar.system-update": "SystemUpdate.qml",
        "bar.toggles": "Toggles.qml",
        "bar.tray": "Tray.qml",
        "bar.weather": "Weather.qml",
        "bar.workspaces": "Workspaces.qml"
      }
      return files[widgetId] || ""
    }

    // Use an absolute file URL. Loader's relative URL base is not reliable
    // when this Repeater is synthesized into the shell module at runtime.
    readonly property string widgetUrl: widgetSource && root.bar && root.bar.shellHost
      ? Util.fileUrl(root.bar.shellHost.shellDir + "/plugins/bar/widgets/" + widgetSource)
      : ""
    source: widgetUrl

    onStatusChanged: if (status === Loader.Error)
      console.warn("BarSection[" + root.section + "] failed " + widgetId + ": " + errorString())

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
      console.log("BarSection loaded", root.section, widgetId, widgetUrl,
        "loader=" + widgetLoader.width + "x" + widgetLoader.height,
        "visible=" + widgetLoader.visible + ",itemVisible=" + item.visible,
        "size=" + item.width + "x" + item.height,
        "implicit=" + item.implicitWidth + "x" + item.implicitHeight)
    }

    onSourceComponentChanged: if (!sourceComponent && widgetId)
      console.warn("BarSection[" + root.section + "]: no registered widget for id '" + widgetId + "'")
  }
}
