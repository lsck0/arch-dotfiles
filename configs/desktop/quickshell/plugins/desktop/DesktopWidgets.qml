pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    property string mainScreenName: ""
    readonly property int taskMax: 4
    readonly property int reminderMax: 4
    readonly property string notesPath: Paths.home + "/sync/notes/notes.md"
    property string notesText: ""
    readonly property int cardWidth: Style.space(520)
    readonly property var reminderRows: {
        var out = [];
        var list = TimerState.reminders || [];
        for (let i = 0; i < list.length && i < root.reminderMax; i++) out.push({
            "label": String(list[i].label || ""),
            "remaining": String(list[i].remaining || "")
        })
        return out;
    }
    readonly property var tasks: Array.prototype.slice.call(TaskState.tasks, 0, root.taskMax)
    readonly property int eventMax: 8
    readonly property var events: Array.prototype.slice.call(CalendarState.events, 0, root.eventMax)
    // the agenda caps each section; surface what the caps hid rather than dropping it silently
    readonly property int hiddenCount: Math.max(0, (TimerState.reminders ? TimerState.reminders.length : 0) - root.reminderMax)
        + Math.max(0, CalendarState.events.length - root.eventMax)
        + Math.max(0, TaskState.tasks.length - root.taskMax)
    readonly property bool agendaEmpty: reminderRows.length === 0 && tasks.length === 0 && events.length === 0

    FileView {
        id: notesFile

        path: root.notesPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.notesText = String(text() || "");
            Util.rearmWatch(this);
        }
        onLoadFailed: root.notesText = ""
        onFileChanged: reload()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel

            required property var modelData

            screen: modelData
            visible: String(modelData.name) === root.mainScreenName
            color: "transparent"
            WlrLayershell.namespace: "quickshell-desktop-widgets"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            ScreenMoveRemap {
                id: screenGuard

                window: panel
            }

            Column {

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Style.bar.sizeHorizontal + Style.spacing.lg
                anchors.rightMargin: Style.spacing.lg
                spacing: Style.spacing.md
                visible: !screenGuard.remapping

                Card {
                    heading: "Pomodoro"
                    visible: TimerState.pomoRunning

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(phaseText.implicitHeight, clockText.implicitHeight)

                        Text {
                            id: phaseText

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: TimerState.pomoPhaseLabel + (TimerState.pomoPaused ? " (paused)" : "")
                            color: Colors.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }

                        Text {
                            id: clockText

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: Util.clock(TimerState.pomoRemainingSeconds)
                            color: TimerState.pomo.phase === "work" ? Colors.accent : Colors.ok
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }

                    }

                    Rectangle {
                        width: parent.width
                        height: Style.spacing.xs
                        radius: Style.shape.data
                        color: Style.selectedFill

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * (TimerState.pomoTotalSeconds > 0 ? Math.max(0, Math.min(1, 1 - TimerState.pomoRemainingSeconds / TimerState.pomoTotalSeconds)) : 0)
                            color: TimerState.pomo.phase === "work" ? Colors.accent : Colors.ok
                        }

                    }

                }

                Card {
                    id: agendaCard

                    heading: "Agenda"
                    visible: !root.agendaEmpty
                    onHeadingClicked: TaskState.panelOpen = true

                    Line {
                        visible: TaskState.activeTask !== null
                        label: TaskState.activeTask ? ("\u25b6 " + TaskState.activeTask.desc) : ""
                        trailing: TaskState.activeElapsedText()
                        trailingColor: Colors.accent
                        trailingOpacity: Style.emphasis.strong
                    }

                    Repeater {
                        model: root.reminderRows

                        delegate: Line {
                            required property var modelData

                            label: modelData.label
                            trailing: modelData.remaining
                            trailingColor: Colors.accent2
                            trailingOpacity: Style.emphasis.strong
                        }

                    }

                    Repeater {
                        model: root.events

                        delegate: Line {
                            required property var modelData

                            label: modelData.summary
                            trailing: modelData.when
                            trailingColor: Colors.accent
                            trailingOpacity: Style.emphasis.strong
                        }

                    }

                    Repeater {
                        model: root.tasks

                        delegate: Line {
                            required property var modelData

                            label: modelData.desc
                            trailing: modelData.due
                            trailingColor: modelData.overdue ? Colors.urgent : Colors.foreground
                        }

                    }

                    Line {
                        visible: root.hiddenCount > 0
                        label: "+" + root.hiddenCount + " more"
                    }

                }

                Card {
                    id: notesCard

                    heading: "Notes"
                    visible: root.notesText.trim().length > 0 || notesEdit.text.length > 0

                    TextEdit {
                        id: notesEdit

                        width: parent.width
                        textFormat: TextEdit.PlainText
                        color: Colors.foreground
                        opacity: (text.length > 0 || activeFocus) ? Style.emphasis.strong : Style.emphasis.faint
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        persistentSelection: true
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        property bool edited: false

                        function save() {
                            saveTimer.stop();
                            if (!edited)
                                return ;

                            edited = false;
                            notesFile.setText(text);
                        }

                        Component.onCompleted: text = root.notesText
                        onTextChanged: if (activeFocus) {
                            edited = true;
                            saveTimer.restart();
                        }
                        onActiveFocusChanged: if (!activeFocus)
                            save()
                        Keys.onEscapePressed: notesEdit.focus = false

                        Timer {
                            id: saveTimer

                            interval: 600
                            onTriggered: notesEdit.save()
                        }

                    }

                    Connections {
                        function onNotesTextChanged() {
                            if (!notesEdit.activeFocus)
                                notesEdit.text = root.notesText;
                        }

                        target: root
                    }

                }

            }

            mask: Region {
                item: notesCard.visible ? notesCard : null

                Region {
                    item: agendaCard.visible ? agendaCard.headingItem : null
                }

            }

        }

    }

    component Card: Rectangle {
        id: card

        property string heading: ""
        default property alias body: bodyCol.data
        readonly property alias headingItem: headingText

        signal headingClicked()

        width: root.cardWidth
        implicitHeight: inner.implicitHeight + Style.spacing.lg * 2
        radius: Style.shape.surface
        color: Util.alpha(Colors.background, 0.72)
        border.width: Style.normalBorderWidth
        border.color: Util.alpha(Colors.accent, Style.surface.ruleAlpha)

        Column {
            id: inner

            x: Style.spacing.lg
            y: Style.spacing.lg
            width: parent.width - Style.spacing.lg * 2
            spacing: Style.spacing.sm

            PanelSectionHeader {
                id: headingText

                text: card.heading

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.headingClicked()
                }

            }

            Column {
                id: bodyCol

                width: parent.width
                spacing: Style.spacing.xs
            }

        }

    }

    component Line: Item {
        property string label: ""
        property string trailing: ""
        property color trailingColor: Colors.foreground
        property real trailingOpacity: Style.emphasis.dim

        width: parent ? parent.width : 0
        implicitHeight: Math.max(labelText.implicitHeight, trailingText.implicitHeight)

        // a long title wraps onto a second line instead of losing its end; the time stays on the first line
        Text {
            id: labelText

            anchors.left: parent.left
            anchors.right: trailingText.left
            anchors.rightMargin: Style.spacing.sm
            anchors.top: parent.top
            textFormat: Text.PlainText
            text: "> " + parent.label
            color: Colors.foreground
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Text {
            id: trailingText

            anchors.right: parent.right
            anchors.baseline: labelText.baseline
            textFormat: Text.PlainText
            text: parent.trailing
            color: parent.trailingColor
            opacity: parent.trailingOpacity
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

    }

}
