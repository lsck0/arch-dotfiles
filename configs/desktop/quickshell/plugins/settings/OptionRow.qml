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
  readonly property bool typed: numeric || ["string", "path", "list", "json", "filesize"].indexOf(type) >= 0
  readonly property var choices: segmented ? option.choices.map(function (c) { return { value: c, label: Schema.choiceLabel(c) } }) : []
  readonly property int pageStart: Schema.choicePageStart(choiceCursor)
  readonly property var page: listed.slice(pageStart, pageStart + Schema.choicePageSize)
    .map(function (c) { return { value: c, label: Schema.choiceLabel(c) } })
  readonly property var tags: {
    var out = [{ text: option.source || "default", color: Colors.menu.text, faint: true }]
    if (option.apply && option.apply !== "live")
      out.push({ text: option.apply, color: option.apply === "relink" ? Colors.accent : option.apply === "relogin" ? Colors.warn : Colors.urgent })
    if (option.scope === "machine") out.push({ text: "machine", color: Colors.menu.text, faint: true })
    if (Schema.resettable(option) && (hasCursor || rowMouse.containsMouse || pending))
      out.push({ text: "reset", color: Colors.accent, reset: true })
    return out
  }

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

        Text {
          width: Math.min(implicitWidth, head.width - tagRow.implicitWidth - head.spacing)
          textFormat: Text.PlainText
          text: (row.hasCursor ? "> " : "  ") + (row.option.label || row.option.key) + (row.pending ? " *" : "")
          color: row.pending ? Colors.accent2 : row.hasCursor ? Colors.menu.selectedText : Colors.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: row.pending
          elide: Text.ElideRight
        }

        Row {
          id: tagRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Repeater {
            model: row.tags

            Text {
              required property var modelData
              textFormat: Text.PlainText
              text: "[" + modelData.text + "]"
              color: modelData.color
              opacity: modelData.faint ? Style.emphasis.faint : 1
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
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

          sourceComponent: ToggleSwitch {
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
            fontSize: Style.font.caption
            onChanged: function (picked) { row.changeRequested(picked) }
          }
        }

        Text {
          visible: row.type === "enum" && !row.segmented
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "[" + Schema.choiceLabel(row.value) + (row.expanded ? " ^]" : " v]")
          color: row.expanded ? Colors.accent : Colors.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body

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

        Text {
          id: browse
          visible: row.type === "path"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "[browse]"
          color: Colors.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
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

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.option.doc || ""
        color: Colors.menu.text
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        visible: row.expanded && (row.choiceFilter !== "" || row.listed.length > Schema.choicePageSize)
        textFormat: Text.PlainText
        text: (row.choiceFilter ? "filter " + row.choiceFilter + ": " : "") + (row.listed.length === 0 ? "no match"
          : (row.pageStart + 1) + "-" + (row.pageStart + row.page.length) + " of " + row.listed.length)
        color: Colors.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Flow {
        width: parent.width
        visible: row.type === "list" || row.expanded
        spacing: Style.spacing.xs

        Repeater {
          model: row.expanded ? row.page : row.type === "list" ? (row.value || []) : []

          Chip {
            required property var modelData
            required property int index
            text: row.expanded ? modelData.label : String(modelData) + "  x"
            selected: row.expanded && row.pageStart + index === row.choiceCursor
            onClicked: {
              if (row.expanded) {
                row.changeRequested(modelData.value)
              } else {
                const list = (row.value || []).slice()
                list.splice(index, 1)
                row.changeRequested(list)
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: row.error !== ""
        textFormat: Text.PlainText
        text: "x " + row.error
        color: Colors.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }
  }
}
