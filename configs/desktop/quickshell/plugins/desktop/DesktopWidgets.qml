pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// ambient desktop cards on the bottom layer: click-through, main screen only, never what the bar
// already shows. an agenda (reminders + taskwarrior), a notes view and the live pomodoro.
Item {
    /*
   * ---------------------------------------------------------------------------
   * CARD PARTS
   * ---------------------------------------------------------------------------
   */
    /*
   * ---------------------------------------------------------------------------
   * SURFACE
   * ---------------------------------------------------------------------------
   */

    id: root

    property string mainScreenName: ""
    // taskwarrior feeds the agenda through TaskState, the one export the bar and the tasks panel share
    readonly property int taskMax: 4
    readonly property int reminderMax: 4
    // in ~/sync (syncthing), so the pad is the same on the desktop and the laptop
    readonly property string notesPath: Paths.home + "/sync/notes/notes.md"
    property string notesText: ""
    readonly property int cardWidth: Style.space(300)
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
    readonly property bool agendaEmpty: reminderRows.length === 0 && tasks.length === 0

    FileView {
        id: notesFile

        path: root.notesPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.notesText = String(text() || "").trim();
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
            // one set of cards, on the main output only
            visible: String(modelData.name) === root.mainScreenName
            color: "transparent"
            WlrLayershell.namespace: "quickshell-desktop-widgets"
            WlrLayershell.layer: WlrLayer.Bottom
            // on demand, not none: the notes card is editable in place, so a click there grabs the keyboard; every
            // other part of the layer stays click-through through the mask below
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // hyprland leaves stale layer position after a monitor moves
            ScreenMoveRemap {
                id: screenGuard

                window: panel
            }

            Column {
                id: stack

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Style.bar.sizeHorizontal + Style.spacing.lg
                anchors.rightMargin: Style.spacing.lg
                spacing: Style.spacing.md
                visible: !screenGuard.remapping

                // live pomodoro, only while a phase runs (the bar carries the controls)
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

                    // elapsed fill over the phase length
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

                // upcoming reminders, then pending tasks
                // the heading opens the full tasks panel (SUPER+o); it is the card's one input region
                Card {
                    id: agendaCard

                    heading: "Agenda"
                    onHeadingClicked: TaskState.panelOpen = true

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
                        model: root.tasks

                        delegate: Line {
                            required property var modelData

                            label: modelData.desc
                            trailing: modelData.due
                            trailingColor: modelData.overdue ? Colors.urgent : Colors.foreground
                        }

                    }

                    Text {
                        width: parent.width
                        visible: root.agendaEmpty
                        textFormat: Text.PlainText
                        text: "nothing scheduled"
                        color: Colors.foreground
                        opacity: Style.emphasis.faint
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }

                }

                // a jot pad in $notesPath, edited in place: this card is the layer's one input region (the mask), so a
                // click starts typing while the rest of the desktop stays click-through. SUPER+SHIFT+n opens the same
                // file in a floating editor for a longer edit, or when a window covers this bottom-layer card
                Card {
                    id: notesCard

                    heading: "Notes"

                    TextEdit {
                        id: notesEdit

                        width: parent.width
                        textFormat: TextEdit.PlainText
                        color: Colors.foreground
                        opacity: (text.length > 0 || activeFocus) ? Style.emphasis.dim : Style.emphasis.faint
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        persistentSelection: true
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        // seed from disk once; later external edits re-seed only while unfocused, never clobbering a
                        // live edit (our own saves reload through the same path)
                        Component.onCompleted: text = root.notesText
                        onTextChanged: if (activeFocus)
                            saveTimer.restart()
                        onActiveFocusChanged: if (!activeFocus)
                            notesFile.setText(text)
                        // a click on the bare desktop passes through the mask and never steals focus back, so Escape is
                        // the way out; clicking any real window releases the keyboard on its own
                        Keys.onEscapePressed: notesEdit.focus = false

                        // the empty-state hint, shown only when there is nothing and the pad is idle
                        Text {
                            anchors.fill: parent
                            visible: notesEdit.text.length === 0 && !notesEdit.activeFocus
                            textFormat: Text.PlainText
                            text: "no notes"
                            color: Colors.foreground
                            opacity: Style.emphasis.faint
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }

                        // debounce writes during a burst of typing; a blur flushes immediately above
                        Timer {
                            id: saveTimer

                            interval: 600
                            onTriggered: notesFile.setText(notesEdit.text)
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

            // only the notes card and the agenda heading are input regions; the pointer passes straight through
            // everywhere else
            mask: Region {
                item: notesCard

                Region {
                    item: agendaCard.headingItem
                }

            }

        }

    }

    // one framed card over the wallpaper: heading rule, then body
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

    // "> label ........ trailing", the shell's terminal list row
    component Line: Item {
        property string label: ""
        property string trailing: ""
        property color trailingColor: Colors.foreground
        property real trailingOpacity: Style.emphasis.dim

        width: parent ? parent.width : 0
        implicitHeight: Math.max(labelText.implicitHeight, trailingText.implicitHeight)

        Text {
            id: labelText

            anchors.left: parent.left
            anchors.right: trailingText.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "> " + parent.label
            color: Colors.foreground
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Text {
            id: trailingText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: parent.trailing
            color: parent.trailingColor
            opacity: parent.trailingOpacity
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }

    }

}
