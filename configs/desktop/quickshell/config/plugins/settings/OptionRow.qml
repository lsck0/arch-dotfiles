pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Schema.js" as Schema

Item {
  id: row

  property var option: ({})
  property var value
  property bool pending: false
  property string error: ""
  property bool hasCursor: false
  property bool expanded: false
  property int choiceCursor: -1
  property var listed: []
  property string choiceFilter: ""
  property bool editing: false
  property string draft: ""

  signal selectRequested()
  signal changeRequested(var value)
  signal resetRequested()
  signal editRequested()
  signal draftEdited(string text)
  signal submitted()
  signal expandRequested()
  signal browseRequested()

  readonly property string type: String(option.type || "")
  readonly property bool numeric: type === "int" || type === "float"
  readonly property bool segmented: Schema.segmented(option)
  readonly property bool multi: type === "multi"
  readonly property bool sequence: type === "sequence"
  readonly property bool picking: multi || sequence || (type === "enum" && !segmented)
  readonly property bool typed: numeric || ["string", "path", "list", "json", "filesize"].indexOf(type) >= 0
  readonly property var choices: segmented ? option.choices.map(function (c) { return { value: c, label: Schema.choiceLabel(row.option, c) } }) : []
  readonly property int pageStart: Schema.choicePageStart(choiceCursor)
  readonly property var page: listed.slice(pageStart, pageStart + Schema.choicePageSize)
    .map(function (c) { return { value: c, label: Schema.choiceLabel(row.option, c) } })
  readonly property var tags: {
    // a pending row says so in a word: accent2Text is near warnText in half the palettes, so colour alone would read as
    // the [relogin] warning beside it
    var out = [pending ? { text: "pending", color: Colors.accent2Text }
      : { text: option.source || "default", color: Colors.menu.text, faint: true }]
    if (option.apply && option.apply !== "live")
      out.push({
        text: option.apply,
        color: ["relink", "apply", "packages"].indexOf(option.apply) >= 0 ? Colors.accentText
          : option.apply === "relogin" ? Colors.warnText : Colors.urgentText
      })
    if (option.scope === "machine") out.push({ text: "machine", color: Colors.menu.text, faint: true })
    if (Schema.resettable(option) && (hasCursor || rowMouse.containsMouse || pending))
      out.push({ text: "reset", color: Colors.accentText, reset: true })
    return out
  }

  readonly property bool lit: hasCursor || rowMouse.containsMouse

  implicitHeight: body.implicitHeight + Style.spacing.sm * 2

  readonly property TextField field: fieldLoader.item as TextField

  function syncField() {
    if (!row.field) return
    var text = row.editing ? row.draft : Schema.toText(row.option, row.value)
    if (row.field.text !== text) row.field.text = text
  }

  onValueChanged: syncField()
  onDraftChanged: syncField()
  onEditingChanged: {
    syncField()
    if (row.editing && row.field) {
      row.field.forceActiveFocus()
      row.field.selectAll()
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.shape.data
    color: row.hasCursor ? Colors.menu.selectedBackground : rowMouse.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: row.selectRequested()
  }

  HudFrame { shown: row.hasCursor }

  Column {
    id: body
    x: Style.spacing.md
    y: Style.spacing.sm
    width: row.width - Style.spacing.md * 2
    spacing: Style.spacing.xxs

    Item {
      width: parent.width
      height: Math.max(head.implicitHeight, Style.row.control)

      Row {
        id: head
        anchors.left: parent.left
        anchors.right: control.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Label {
          width: Math.min(implicitWidth, head.width - tagRow.implicitWidth - head.spacing)
          text: (row.hasCursor ? "> " : "  ") + (row.option.label || row.option.key) + (row.pending ? " *" : "")
          color: row.pending ? Colors.accent2Text : row.hasCursor ? Colors.menu.selectedText : Colors.menu.text
          font.bold: row.pending
          font.capitalization: Font.AllUppercase
          font.letterSpacing: Style.labelTracking
          elide: Text.ElideRight
        }

        Row {
          id: tagRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Repeater {
            model: row.tags

            Label {
              required property var modelData
              text: "[" + modelData.text + "]"
              color: modelData.faint && !row.lit ? Colors.textDim : modelData.color
              caption: true
              font.bold: !modelData.faint

              MouseArea {
                anchors.fill: parent
                enabled: parent.modelData.reset === true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.resetRequested()
              }
            }
          }
        }
      }

      Item {
        id: control
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(280)
        height: parent.height

        Loader {
          active: row.type === "bool"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          sourceComponent: Toggle {
            checked: row.value === true
            interactive: false
            hasCursor: row.hasCursor

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: row.changeRequested(!row.value)
            }
          }
        }

        Loader {
          active: row.type === "enum" && row.segmented
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          sourceComponent: ButtonGroup {
            options: row.choices
            value: String(row.value)
            focusable: false
            onChanged: function (picked) { row.changeRequested(row.option.choices.find(function (c) { return String(c) === picked })) }
          }
        }

        Label {
          visible: row.picking
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "[" + (row.multi ? (row.value || []).length + "/" + (row.option.choices || []).length
            : row.sequence ? "add" : Schema.choiceLabel(row.option, row.value))
            + (row.expanded ? " ^]" : " v]")
          color: row.expanded ? Colors.accentText : Colors.menu.text

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.expandRequested()
          }
        }

        Loader {
          active: Schema.sliderable(row.option)
          anchors.left: parent.left
          anchors.right: fieldLoader.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter

          sourceComponent: Slider {
            activeFocusOnTab: false
            value: Number(row.value) || 0
            minimum: Number(row.option.min)
            maximum: Number(row.option.max)
            step: Schema.step(row.option)
            integer: row.type === "int"
            onReleased: function (picked) { row.changeRequested(Schema.snap(row.option, picked)) }
          }
        }

        Loader {
          id: fieldLoader
          active: row.typed
          anchors.right: browse.visible ? browse.left : parent.right
          anchors.rightMargin: browse.visible ? Style.spacing.sm : 0
          anchors.verticalCenter: parent.verticalCenter
          width: row.numeric || row.type === "filesize" ? Style.space(96) : parent.width - (browse.visible ? browse.width + Style.spacing.sm : 0)
          onLoaded: row.syncField()

          sourceComponent: TextField {
            verticalPadding: Style.spacing.xs
            activeFocusOnTab: false
            hasCursor: row.hasCursor && !row.editing
            horizontalAlignment: row.numeric || row.type === "filesize" ? TextInput.AlignRight : TextInput.AlignLeft
            placeholderText: row.type === "list" ? "add an entry" : ""

            onTextEdited: row.draftEdited(text)
            onActiveFocusChanged: if (activeFocus && !row.editing) row.editRequested()

            Keys.onPressed: function (event) {
              if (event.accepted) return
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                row.submitted()
                event.accepted = true
              } else if (event.key === Qt.Key_Backspace && row.type === "list" && text === "") {
                const list = row.value || []
                if (list.length > 0) row.changeRequested(list.slice(0, -1))
                event.accepted = true
              }
            }
          }
        }

        Label {
          visible: row.type === "fixed"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: Schema.toText(row.option, row.value)
          dim: true
          elide: Text.ElideMiddle
        }

        Label {
          id: browse
          visible: row.type === "path"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "[browse]"
          color: Colors.accentText
          caption: true
          font.bold: true

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.browseRequested()
          }
        }
      }
    }

    Column {
      x: Style.spacing.lg
      width: parent.width - x
      spacing: Style.spacing.xs

      Label {
        width: parent.width
        visible: row.expanded && (row.choiceFilter !== "" || row.listed.length > Schema.choicePageSize)
        text: (row.listed.length === 0 ? "> NO MATCH"
          : (row.pageStart + 1) + "-" + (row.pageStart + row.page.length) + " OF " + row.listed.length)
          + (row.choiceFilter ? " :: " + row.choiceFilter : "")
        color: Colors.accentText
        caption: true
      }

      // the value: a list's and a sequence's entries, each removed by its x; a multi's picks open its choices
      Flow {
        width: parent.width
        visible: row.type === "list" || row.sequence || (row.multi && !row.expanded)
        spacing: Style.spacing.xs

        Repeater {
          model: parent.visible ? (row.value || []) : []

          Button {
            variant: "chip"
            required property var modelData
            required property int index
            text: Schema.choiceLabel(row.option, modelData) + (row.multi ? "" : "  x")
            selected: row.multi
            onClicked: {
              if (row.multi) {
                row.expandRequested()
                return
              }
              const list = (row.value || []).slice()
              list.splice(index, 1)
              row.changeRequested(list)
            }
          }
        }
      }

      Flow {
        width: parent.width
        visible: row.expanded
        spacing: Style.spacing.xs

        Repeater {
          model: row.expanded ? row.page : []

          Button {
            variant: "chip"
            required property var modelData
            required property int index
            readonly property bool cursor: row.pageStart + index === row.choiceCursor
            text: (row.sequence ? "+ " : "") + modelData.label
            selected: row.multi ? (row.value || []).indexOf(modelData.value) >= 0 : cursor
            hasCursor: (row.multi || row.sequence) && cursor
            onClicked: row.changeRequested(Schema.choicePicked(row.option, row.value, modelData.value))
          }
        }
      }

      Label {
        width: parent.width
        visible: row.error !== ""
        text: "x " + row.error
        color: Colors.urgentText
        caption: true
        wrapMode: Text.Wrap
      }
    }
  }
}
