pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "../../services"
import "../../services/AppSearch.js" as AppSearch

Item {
  id: root

  property AppLibrary appLibrary: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var rows: []

  property color foreground: Colors.menu.text
  property color selectedBackground: Colors.menu.selectedBackground
  property color selectedText: Colors.menu.selectedText
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(44)
  property int iconSize: Style.space(28)

  readonly property var prefixes: ({ "=": "calc", ">": "run", "@": "windows", "?": "keys" })
  readonly property string mode: prefixes[filterText.charAt(0)] || "apps"
  readonly property string modeQuery: mode === "apps" ? filterText : filterText.substring(1).trim()

  readonly property var modeTitles: ({ apps: "applications", calc: "calculator", run: "run", windows: "windows", keys: "keybinds" })
  readonly property var modePlaceholders: ({ apps: "search applications", calc: "enter an expression", run: "command to run", windows: "search windows", keys: "search keybinds" })
  readonly property var modeHints: ({
    apps: [["ENTER", "open"], ["=", "calc"], [">", "run"], ["@", "windows"], [":", "clipboard"], ["?", "keys"], ["ESC", "close"]],
    calc: [["ENTER", "copy"], ["ESC", "clear"]],
    run: [["ENTER", "run"], ["ESC", "clear"]],
    windows: [["^/v", "select"], ["ENTER", "focus"], ["ESC", "clear"]],
    keys: [["^/v", "select"], ["ENTER", "close"], ["ESC", "clear"]]
  })

  readonly property var modifierBits: [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
  // hyprctl names that the hint grammar spells differently; every other key name is shown upper case
  readonly property var keyNames: ({ "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB", "Return": "ENTER",
                                     "Escape": "ESC", "Delete": "DEL" })
  property var binds: []
  property string bindsState: ""

  readonly property int calcDebounceMs: 150
  property string calcResult: ""
  property string calcState: ""
  readonly property int exitNotFound: 127
  readonly property int calcTimeoutS: 5

  function open() {
    var focused = Hyprland.focusedMonitor
    panel.screen = Array.from(Quickshell.screens).find(function (s) { return focused && s.name === focused.name }) || null
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
    bindsProc.running = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function appRows() {
    if (!root.appLibrary) return []
    var entries = root.appLibrary.sortedEntries(root.modeQuery)
    var out = []
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i]
      const name = root.appLibrary.entryName(e)
      const sub = root.appLibrary.entrySubtext(e)
      out.push({ kind: "app", name: name, sub: sub.toLowerCase() === name.toLowerCase() ? "" : sub,
                 icon: root.appLibrary.iconSource(e.icon), glyph: "", keys: "", payload: e })
    }
    return out
  }

  function windowRows() {
    var q = root.modeQuery.toLowerCase()
    var values = Hyprland.toplevels.values
    var out = []
    for (let i = 0; i < values.length; i++) {
      const t = values[i]
      const cls = t.wayland ? String(t.wayland.appId || "") : ""
      const title = String(t.title || "")
      if (q && (title + " " + cls).toLowerCase().indexOf(q) < 0) continue
      const ws = t.workspace ? String(t.workspace.id) : "--"
      out.push({ kind: "window", name: title || cls || "--", sub: "[" + ws + "] " + cls,
                 icon: cls ? Util.iconSource(cls.toLowerCase()) : "", glyph: "\u{f2d0}", keys: "", payload: String(t.address || "") })
    }
    return out
  }

  function calcRows() {
    if (!root.modeQuery) return []
    var text = root.calcState === "missing" ? "x ERR qalc is not installed"
      : root.calcState === "error" ? "x ERR"
      : root.calcState === "loading" && !root.calcResult ? "--"
      : root.calcResult
    return [{ kind: "calc", name: "= " + text, sub: root.modeQuery, icon: "", glyph: "\u{f00ec}", keys: "", payload: root.calcResult }]
  }

  function runRows() {
    if (!root.modeQuery) return []
    return [{ kind: "run", name: root.modeQuery, sub: "sh -c", icon: "", glyph: "\u{f018d}", keys: "", payload: root.modeQuery }]
  }

  function bindKeys(bind) {
    var parts = []
    for (let i = 0; i < root.modifierBits.length; i++) {
      if (bind.modmask & root.modifierBits[i][0]) parts.push(root.modifierBits[i][1])
    }
    const key = String(bind.key || "")
    parts.push(bind.catch_all ? "ANY"
      : root.keyNames[key] || key.toUpperCase() || "CODE:" + bind.keycode)
    return parts.join("+")
  }

  function bindRows() {
    var words = root.modeQuery.toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 })
    var topLevel = []
    var submaps = []
    for (let i = 0; i < root.binds.length; i++) {
      const b = root.binds[i]
      const keys = root.bindKeys(b)
      const name = String(b.description || "") || String(b.dispatcher || "") + " " + String(b.arg || "")
      const sub = b.submap ? "[" + b.submap + "]" : ""
      const haystack = (name + " " + keys + " " + sub).toLowerCase()
      if (!words.every(function(w) { return haystack.indexOf(w) >= 0 })) continue
      const row = { kind: "bind", name: name, sub: sub, icon: "", glyph: "\u{f030c}", keys: keys, payload: "" }
      if (b.submap) submaps.push(row)
      else topLevel.push(row)
    }
    return topLevel.concat(submaps)
  }

  function rebuild() {
    root.rows = root.mode === "calc" ? calcRows()
      : root.mode === "run" ? runRows()
      : root.mode === "windows" ? windowRows()
      : root.mode === "keys" ? bindRows()
      : appRows()
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function setFilter(text) {
    if (text === ":") {
      root.close()
      Quickshell.execDetached(Paths.ipcCall("clipboard", "open"))
      return
    }
    const wasKeys = root.mode === "keys"
    root.filterText = text
    root.selectedIndex = 0
    if (root.mode === "keys" && !wasKeys) {
      root.binds = []
      root.bindsState = "loading"
      bindsProc.running = true
    }
    if (root.mode === "calc") {
      root.calcState = root.modeQuery ? "loading" : ""
      if (root.modeQuery) calcDebounce.restart()
      else calcDebounce.stop()
    }
    root.rebuild()
  }

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
      const address = row.payload.indexOf("0x") === 0 ? row.payload : "0x" + row.payload
      Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + address + "' })")
    } else if (row.kind === "calc") {
      if (root.calcState !== "" || !row.payload) return
      Quickshell.execDetached(["wl-copy", "--", row.payload])
    } else if (row.kind === "run") {
      Quickshell.execDetached(["uwsm-app", "--", "sh", "-c", row.payload])
    }
    root.close()
  }

  Timer {
    id: calcDebounce
    interval: root.calcDebounceMs
    onTriggered: {
      calcProc.running = false
      calcProc.command = ["sh", "-c", "command -v qalc >/dev/null 2>&1 || exit " + root.exitNotFound + "; exec timeout " + root.calcTimeoutS + " qalc -t \" $1\"",
                          "qalc", root.modeQuery]
      calcProc.running = true
    }
  }

  Process {
    id: calcProc
    stdout: StdioCollector { id: calcOut; waitForEnd: true }
    onExited: function(code) {
      if (root.mode !== "calc" || calcProc.command[4] !== root.modeQuery) return
      var text = String(calcOut.text || "").trim().split("\n").pop()
      root.calcState = code === root.exitNotFound ? "missing" : code !== 0 || !text ? "error" : ""
      root.calcResult = root.calcState === "" ? text : ""
      root.rebuild()
    }
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector { id: bindsOut; waitForEnd: true }
    onExited: function(code) {
      try {
        root.binds = code === 0 ? JSON.parse(bindsOut.text) : []
        root.bindsState = code === 0 ? "" : "error"
      } catch (e) {
        root.binds = []
        root.bindsState = "error"
      }
      if (root.mode === "keys") root.rebuild()
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
    placeholder: root.modePlaceholders[root.mode]
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
          root.selectAt(root.selectedIndex - resultList.pageRows)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.selectAt(root.selectedIndex + resultList.pageRows)
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
        } else if (Util.isWordDelete(event.key, event.modifiers)) {
          root.setFilter(Util.wordDelete(root.filterText))
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
      readonly property int rowPitch: root.rowHeight + spacing
      readonly property int pageRows: Math.max(1, Math.floor((parent.height + spacing) / rowPitch))
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: pageRows * rowPitch - spacing
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
            color: Colors.accentText
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
            width: parent.width - root.iconSize - cursorMark.width - keysLabel.width - parent.spacing * 3

            Text {
              width: parent.width
              textFormat: Text.StyledText
              text: rowDelegate.modelData.kind === "app"
                ? AppSearch.highlight(rowDelegate.modelData.name, root.modeQuery, String(Colors.accent2))
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
              color: rowDelegate.selected ? root.selectedText : Colors.textDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            id: keysLabel
            anchors.verticalCenter: parent.verticalCenter
            width: text ? implicitWidth : 0
            textFormat: Text.PlainText
            text: rowDelegate.modelData.keys
            color: rowDelegate.selected ? root.selectedText : Colors.accentText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        HudFrame { shown: rowDelegate.selected }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activateAt(rowDelegate.index)
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        opacity: root.rows.length === 0 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }
        width: parent.width * 0.8

        Text {
          textFormat: Text.PlainText
          text: "\u{f003b}"
          color: Colors.accentText
          opacity: Style.emphasis.dim
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.display
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: root.mode === "keys" && root.bindsState === "loading" ? "> LOADING"
            : root.mode === "keys" && root.bindsState === "error" ? "> HYPRCTL BINDS FAILED"
            : root.modeQuery ? "> NO MATCH"
            : root.mode === "apps" ? "> NOTHING HERE"
            : root.mode === "calc" ? "> TYPE AN EXPRESSION"
            : root.mode === "run" ? "> TYPE A COMMAND"
            : root.mode === "windows" ? "> NO WINDOWS"
            : "> NO KEYBINDS"
          color: Colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }
      }
    }
  }
}
