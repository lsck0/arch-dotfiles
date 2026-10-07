import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../../services"
import "../../services/AppSearch.js" as AppSearch

// launcher: apps by default; a leading `=` calculates, `>` runs a command, `@` lists windows, `:` hands off to the clipboard
Item {
  id: root

  property AppLibrary appLibrary: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  // uniform rows: { kind, name, sub, icon, glyph, payload }
  property var rows: []

  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(44)
  property int iconSize: Style.space(28)

  readonly property var prefixes: ({ "=": "calc", ">": "run", "@": "windows" })
  readonly property string mode: prefixes[filterText.charAt(0)] || "apps"
  readonly property string modeQuery: mode === "apps" ? filterText : filterText.substring(1).trim()

  readonly property var modeTitles: ({ apps: "applications", calc: "calculator", run: "run", windows: "windows" })
  readonly property var modeHints: ({
    apps: [["ESC", "close"], ["^ v", "select"], ["ENTER", "run"], ["= > @ :", "modes"]],
    calc: [["ESC", "clear"], ["ENTER", "copy"]],
    run: [["ESC", "clear"], ["ENTER", "run"]],
    windows: [["ESC", "clear"], ["^ v", "select"], ["ENTER", "focus"]]
  })

  // qalc is slow to start, so the calculator waits for typing to pause
  readonly property int calcDebounceMs: 150
  property string calcResult: ""
  // "", "loading", "error", "missing"
  property string calcState: ""
  // qalc exits 127 through the wrapper when it is not installed
  readonly property int exitNotFound: 127
  // a stuck qalc (currency update, huge factorial) must not hold the row on `--`
  readonly property int calcTimeoutS: 5

  function open() {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    calcDebounce.stop()
    calcProc.running = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function appRows() {
    if (!root.appLibrary) return []
    var entries = root.appLibrary.sortedEntries(root.modeQuery)
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      out.push({ kind: "app", name: root.appLibrary.entryName(e), sub: root.appLibrary.entrySubtext(e),
                 icon: root.appLibrary.iconSource(e.icon), glyph: "", payload: e })
    }
    return out
  }

  function windowRows() {
    var q = root.modeQuery.toLowerCase()
    var values = Hyprland.toplevels.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      // the wayland app id is the class, no ipc refresh needed
      var cls = t.wayland ? String(t.wayland.appId || "") : ""
      var title = String(t.title || "")
      if (q && (title + " " + cls).toLowerCase().indexOf(q) < 0) continue
      var ws = t.workspace ? String(t.workspace.id) : "--"
      out.push({ kind: "window", name: title || cls || "--", sub: "[" + ws + "] " + cls,
                 icon: cls ? Util.iconSource(cls.toLowerCase()) : "", glyph: "\u{f2d0}", payload: String(t.address || "") })
    }
    return out
  }

  function calcRows() {
    if (!root.modeQuery) return []
    var text = root.calcState === "missing" ? "x ERR qalc is not installed"
      : root.calcState === "error" ? "x ERR"
      : root.calcState === "loading" && !root.calcResult ? "--"
      : root.calcResult
    return [{ kind: "calc", name: "= " + text, sub: root.modeQuery, icon: "", glyph: "\u{f00ec}", payload: root.calcResult }]
  }

  function runRows() {
    if (!root.modeQuery) return []
    return [{ kind: "run", name: root.modeQuery, sub: "sh -c", icon: "", glyph: "\u{f018d}", payload: root.modeQuery }]
  }

  function rebuild() {
    root.rows = root.mode === "calc" ? calcRows()
      : root.mode === "run" ? runRows()
      : root.mode === "windows" ? windowRows()
      : appRows()
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function setFilter(text) {
    // `:` belongs to the clipboard overlay, one history browser in the shell
    if (text === ":") {
      root.close()
      Quickshell.execDetached(Paths.ipcCall("clipboard", "open"))
      return
    }
    root.filterText = text
    root.selectedIndex = 0
    if (root.mode === "calc") {
      root.calcState = root.modeQuery ? "loading" : ""
      if (root.modeQuery) calcDebounce.restart()
      else calcDebounce.stop()
    }
    root.rebuild()
  }

  // clamps, so an empty list keeps index 0 instead of -1
  function selectAt(index) {
    root.selectedIndex = Math.max(0, Math.min(index, root.rows.length - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateAt(index) {
    if (index < 0 || index >= root.rows.length) return
    var row = root.rows[index]
    if (row.kind === "app") {
      if (!root.appLibrary) return
      root.appLibrary.launch(row.payload.id, row.name)
    } else if (row.kind === "window") {
      if (!row.payload) return
      var address = row.payload.indexOf("0x") === 0 ? row.payload : "0x" + row.payload
      Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + address + "' })")
    } else if (row.kind === "calc") {
      if (root.calcState !== "" || !row.payload) return
      Quickshell.execDetached(["wl-copy", "--", row.payload])
    } else if (row.kind === "run") {
      // uwsm-app so the command does not inherit wayland-wm@.service
      Quickshell.execDetached(["uwsm-app", "--", "sh", "-c", row.payload])
    }
    root.close()
  }

  Timer {
    id: calcDebounce
    interval: root.calcDebounceMs
    onTriggered: {
      calcProc.running = false
      // leading space: an expression starting with - is not read as an option
      calcProc.command = ["sh", "-c", "command -v qalc >/dev/null 2>&1 || exit " + root.exitNotFound + "; exec timeout " + root.calcTimeoutS + " qalc -t \" $1\"",
                          "qalc", root.modeQuery]
      calcProc.running = true
    }
  }

  Process {
    id: calcProc
    stdout: StdioCollector { id: calcOut; waitForEnd: true }
    onExited: function(code) {
      // a superseded run, killed for the newer query
      if (root.mode !== "calc" || calcProc.command[4] !== root.modeQuery) return
      var text = String(calcOut.text || "").trim().split("\n").pop()
      root.calcState = code === root.exitNotFound ? "missing" : code !== 0 || !text ? "error" : ""
      root.calcResult = root.calcState === "" ? text : ""
      root.rebuild()
    }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened && root.mode === "apps") root.rebuild() }
  }

  Connections {
    target: Hyprland.toplevels
    enabled: root.opened && root.mode === "windows"
    function onValuesChanged() { root.rebuild() }
  }

  IpcHandler {
    target: "appsearch"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened
    name: "appsearch"
    title: root.modeTitles[root.mode]
    suffix: "[" + String(root.rows.length) + "]"
    prompt: true
    query: root.filterText
    placeholder: "search applications"
    hints: root.modeHints[root.mode]
    cardWidth: Style.space(560)
    cardHeight: Style.space(480)
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectAt(root.selectedIndex - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectAt(root.selectedIndex + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.selectAt(root.selectedIndex - 6)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.selectAt(root.selectedIndex + 6)
          event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          root.selectAt(0)
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          root.selectAt(root.rows.length - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateAt(root.selectedIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.setFilter(root.filterText.slice(0, -1))
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }
    }

    ListView {
      id: resultList
      anchors.fill: parent
      clip: true
      model: root.rows
      spacing: Style.spacing.xxs
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: rowDelegate
        required property var modelData
        required property int index
        readonly property bool selected: index === root.selectedIndex

        width: ListView.view.width
        height: root.rowHeight
        radius: Style.shape.data
        opacity: panel.boot.rowOpacity(index)
        color: selected ? root.selectedBackground
          : rowMouse.containsMouse ? Style.hoverFill : "transparent"

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md
          spacing: Style.spacing.md

          Text {
            id: cursorMark
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.md
            textFormat: Text.PlainText
            text: rowDelegate.selected ? ">" : ""
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            layer.enabled: rowDelegate.selected && Style.fx.glow > 0
            layer.effect: Glow {}
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize

            Image {
              id: rowIcon
              anchors.fill: parent
              visible: source !== "" && status === Image.Ready
              sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
              sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              source: rowDelegate.modelData.icon
            }

            Text {
              anchors.centerIn: parent
              visible: !rowIcon.visible
              textFormat: Text.PlainText
              text: rowDelegate.modelData.glyph
              color: rowDelegate.selected ? root.selectedText : root.foreground
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.heading
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.iconSize - cursorMark.width - parent.spacing * 2

            Text {
              width: parent.width
              // matched chars light up; markup is escaped by AppSearch.highlight
              textFormat: Text.StyledText
              text: rowDelegate.modelData.kind === "app"
                ? AppSearch.highlight(rowDelegate.modelData.name, root.modeQuery, String(Color.accent2))
                : AppSearch.escapeHtml(rowDelegate.modelData.name)
              color: rowDelegate.selected ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: text.length > 0
              text: rowDelegate.modelData.sub
              color: rowDelegate.selected ? root.selectedText : root.foreground
              opacity: Style.emphasis.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        HudFrame { shown: rowDelegate.selected }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // hover deliberately does not move the selection
          onClicked: root.activateAt(rowDelegate.index)
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        visible: root.rows.length === 0
        width: parent.width * 0.8

        Text {
          textFormat: Text.PlainText
          text: "\u{f003b}"
          color: root.selectedText
          opacity: Style.emphasis.dim
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.display
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: root.mode === "apps" || root.modeQuery ? "> NOTHING HERE" : "> TYPE AN EXPRESSION"
          color: root.foreground
          opacity: Style.emphasis.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }
      }
    }
  }
}
