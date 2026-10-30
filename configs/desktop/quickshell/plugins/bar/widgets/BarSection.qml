pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Repeater {
  id: root

  required property var bar
  required property string section

  // slot indices the bar dropped to fit its width; each kept widget after the first takes its gap as a left margin,
  // so a hidden or dropped one leaves none behind
  property var dropped: ({})
  property real spacing: 0
  property int loadedRevision: 0

  // the visible, non-empty widgets in this section's drop order: lowest barPriority first, ties from the end farthest
  // from the screen edge
  readonly property var candidates: {
    void loadedRevision
    var widgets = []
    for (let i = 0; i < count; i++) {
      const slot = itemAt(i) as Loader
      const widget = slot ? slot.item as BarWidget : null
      if (!widget || !widget.visible || widget.implicitWidth <= 0) continue
      widgets.push({ index: i, width: widget.implicitWidth, priority: widget.barPriority })
    }
    var inward = section === "right" ? 1 : -1
    widgets.sort(function(a, b) { return a.priority - b.priority || inward * (a.index - b.index) })
    for (let i = 0; i < widgets.length; i++) widgets[i].order = i
    return widgets
  }

  readonly property int firstKept: {
    var first = count
    for (const widget of candidates) if (!dropped[widget.index]) first = Math.min(first, widget.index)
    return first
  }

  onItemAdded: loadedRevision++
  model: bar && bar.layoutConfig ? bar.layoutConfig[section] : []

  delegate: Loader {
    id: widgetLoader
    required property string modelData
    required property int index

    source: Util.fileUrl(Paths.barWidget(modelData + ".qml"))

    onStatusChanged: if (status === Loader.Error) {
      var detail = sourceComponent ? sourceComponent.errorString() : "(no detail)"
      console.warn("BarSection[" + root.section + "] failed " + modelData + ": " + detail)
    }

    readonly property var widget: item
    readonly property bool dropped: root.dropped[index] === true
    readonly property bool shown: !!widget && widget.visible && widget.implicitWidth > 0 && !dropped

    // visible stays true so widget.visible keeps reporting the widget's own state to the drop pass
    visible: true
    opacity: dropped ? 0 : 1
    enabled: !dropped
    Layout.minimumWidth: 0
    Layout.leftMargin: shown && index > root.firstKept ? root.spacing : 0
    Layout.preferredWidth: shown ? widget.implicitWidth : 0
    Layout.maximumWidth: shown ? widget.implicitWidth : 0
    Layout.minimumHeight: 0
    Layout.preferredHeight: shown ? widget.implicitHeight : 0
    Layout.maximumHeight: shown ? widget.implicitHeight : 0

    readonly property var settings: root.bar && root.bar.shellHost
      ? root.bar.shellHost.settingsForWidget(modelData) : ({})
    onSettingsChanged: if (widget && "settings" in widget) widget.settings = settings
    onDroppedChanged: if (widget && "dropped" in widget) widget.dropped = dropped

    onLoaded: {
      root.loadedRevision++
      if (!widget) return
      if ("bar" in widget) widget.bar = root.bar
      if ("settings" in widget) widget.settings = widgetLoader.settings
      if ("dropped" in widget) widget.dropped = widgetLoader.dropped
    }
  }
}
