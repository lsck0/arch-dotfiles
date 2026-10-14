pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Schema.js" as Schema

// state lives in Settings.qml, changes go back as signals
Item {
  id: row

  property var option: ({})
  property var value
  property bool pending: false
  property string error: ""
  property bool hasCursor: false
  property bool expanded: false
  property int choiceCursor: -1
  // the open list's choices after its filter
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
  readonly property var choices: (option.choices || []).map(function (c) { return { value: c, label: Schema.choiceLabel(c) } })
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

  function syncField() {
    var text = row.editing ? row.draft : Schema.toText(row.option, row.value)
    if (field.text !== text) field.text = text
  }

  onValueChanged: syncField()
  onDraftChanged: syncField()
  onEditingChanged: {
    syncField()
    if (row.editing) {
      field.forceActiveFocus()
      field.selectAll()
    }
  }
  Component.onCompleted: syncField()

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

        ToggleSwitch {
          visible: row.type === "bool"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: row.value === true
          interactive: false
          hasCursor: row.hasCursor

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.changeRequested(!row.value)
          }
        }

        ButtonGroup {
          visible: row.type === "enum" && Schema.segmented(row.option)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          options: row.choices
          value: String(row.value)
          focusable: false
          fontSize: Style.font.caption
          onChanged: function (picked) { row.changeRequested(picked) }
        }

        Text {
          visible: row.type === "enum" && !Schema.segmented(row.option)
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

        Slider {
          visible: row.numeric
          anchors.left: parent.left
          anchors.right: field.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          activeFocusOnTab: false
          value: Number(row.value) || 0
          minimum: Number(row.option.min !== undefined ? row.option.min : 0)
          maximum: Number(row.option.max !== undefined ? row.option.max : 100)
          step: Schema.step(row.option)
          integer: row.type === "int"
          onReleased: function (picked) { row.changeRequested(Schema.snap(row.option, picked)) }
        }

        TextField {
          id: field
          visible: row.numeric || ["string", "path", "list", "json"].indexOf(row.type) >= 0
          anchors.right: browse.visible ? browse.left : parent.right
          anchors.rightMargin: browse.visible ? Style.spacing.sm : 0
          anchors.verticalCenter: parent.verticalCenter
          width: row.numeric ? Style.space(72) : parent.width - (browse.visible ? browse.width + Style.spacing.sm : 0)
          verticalPadding: Style.spacing.xs
          activeFocusOnTab: false
          hasCursor: row.hasCursor && !row.editing
          horizontalAlignment: row.numeric ? TextInput.AlignRight : TextInput.AlignLeft
          placeholderText: row.type === "list" ? "add an entry" : ""

          onTextEdited: row.draftEdited(text)
          onActiveFocusChanged: if (activeFocus && !row.editing) row.editRequested()

          Keys.onPressed: function (event) {
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
