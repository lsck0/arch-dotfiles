import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Native workspace overview — `Super+Tab` used to be bound to
// `hl.dsp.global("overview:toggle")`, a global shortcut name no installed
// plugin ever registered (checked: `hyprctl plugin list` shows only
// dynamic-cursors; hyprexpo was never added to hyprpm and isn't built into
// this Hyprland version). Rather than gambling on a third-party C++ plugin
// building against this exact Hyprland version (hy3 is already broken here
// for that reason — `hyprpm list` shows it failed to build), this is a
// plain QML grid: one tile per existing workspace, each listing its
// windows by title. No live thumbnails (that needs wlr-screencopy per
// window, real scope beyond what was asked) — titles are enough to tell
// workspaces apart and jump to one.
Item {
    // Number keys jump straight to a workspace, the way Super+<n> already does
    // outside the overview — arrows alone meant walking across the grid to
    // reach a workspace you could already name. 0 is workspace 10, matching
    // both the bar widget's labelling and the compositor's own binds.

    id: root

    property bool opened: false
    property int selectedIndex: 0

    function workspaceList() {
        var values = Hyprland.workspaces.values;
        var ids = [];
        for (var i = 0; i < values.length; i++) {
            var id = values[i].id;
            if (id > 0)
                ids.push(id);

        }
        ids.sort(function(left, right) {
            return left - right;
        });
        return ids;
    }

    function open() {
        var ids = root.workspaceList();
        var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1;
        var idx = ids.indexOf(focusedId);
        root.selectedIndex = idx >= 0 ? idx : 0;
        root.opened = true;
        Qt.callLater(function() {
            keyCatcher.forceActiveFocus();
        });
    }

    function close() {
        root.opened = false;
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    function focusAndClose(id) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + id + "\" })"]);
        root.close();
    }

    // Deliberately NOT restricted to workspaces that currently exist: an
    // overview that refuses to send you to an empty workspace 4 behaves
    // differently from the Super+4 muscle memory it sits on top of. Hyprland
    // creates it, same as it always does.
    function jumpToWorkspace(number) {
        root.focusAndClose(number);
    }

    IpcHandler {
        function toggle() : string {
            root.toggle();
            return "ok";
        }

        function open() : string {
            root.open();
            return "ok";
        }

        function close() : string {
            root.close();
            return "ok";
        }

        target: "overview"
    }

    PanelWindow {
        id: panel

        visible: root.opened
        color: "transparent"
        WlrLayershell.namespace: "quickshell-overview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: Color.menu.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keyCatcher

            readonly property var ids: root.opened ? root.workspaceList() : []
            readonly property int columns: Math.min(5, Math.max(1, ids.length))

            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                var ids = keyCatcher.ids;
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.selectedIndex = Math.min(ids.length - 1, root.selectedIndex + 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - keyCatcher.columns);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.selectedIndex = Math.min(ids.length - 1, root.selectedIndex + keyCatcher.columns);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (ids.length > 0)
                        root.focusAndClose(ids[root.selectedIndex]);

                    event.accepted = true;
                } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    root.jumpToWorkspace(event.key - Qt.Key_0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_0) {
                    root.jumpToWorkspace(10);
                    event.accepted = true;
                }
            }

            // Titled composition rather than a bare floating grid: a header that
            // says what this is, the grid, and a key legend. The overview is a
            // full-screen takeover — with no framing at all it read as a small
            // strip of thumbnails dropped on the desktop.
            Column {
                anchors.centerIn: parent
                spacing: Style.spacing.huge

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spacing.md

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "WORKSPACES"
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                        font.bold: true
                        font.letterSpacing: Style.headerTracking
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: String(keyCatcher.ids.length)
                        color: Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                    }

                }

                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: keyCatcher.columns
                    spacing: Style.spacing.xl

                    Repeater {
                        model: keyCatcher.ids

                        BorderSurface {
                            id: tile

                            required property var modelData
                            required property int index
                            readonly property var workspace: {
                                var values = Hyprland.workspaces.values;
                                for (var i = 0; i < values.length; i++) if (values[i].id === modelData) {
                                    return values[i];
                                }
                                return null;
                            }
                            readonly property var toplevels: workspace ? workspace.toplevels.values : []
                            // The live thumbnail shows this workspace's most recently
                            // active window — the one Hyprland itself would raise on
                            // switch — not just array position 0.
                            readonly property var primaryToplevel: {
                                for (var i = 0; i < toplevels.length; i++) if (toplevels[i].activated) {
                                    return toplevels[i];
                                }
                                return toplevels.length > 0 ? toplevels[0] : null;
                            }
                            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                            readonly property bool selected: index === root.selectedIndex

                            // 16:9, matching the actual screen the thumbnail is a photo of.
                            // Selected/unselected treatment borrowed directly from the
                            // wallpaper picker (plugins/image-picker/ImagePicker.qml): the
                            // selected item pops in size and full brightness, everything
                            // else dims — same Color.imagePicker tokens, same 0.42 dim
                            // alpha, same grammar, not a new one.
                            // Sized off the actual output rather than fixed: at a flat 320px
                            // four tiles filled a third of a 1920 screen and the overview
                            // read as a strip. Capped so a single workspace does not become
                            // a poster, floored so a full grid stays legible.
                            width: Math.max(Style.space(260), Math.min(Style.space(460), (keyCatcher.width - Style.space(160)) / keyCatcher.columns - Style.spacing.xl))
                            height: Math.round(width * 9 / 16)
                            scale: selected ? 1.08 : 1
                            z: selected ? 10 : 0
                            radius: Style.cornerRadius
                            color: Color.menu.background
                            borderSpec: Border.controlSpec(selected ? "selected" : "normal", Color.menu.text, Color.accent)
                            clip: true

                            ScreencopyView {
                                id: capture

                                anchors.fill: parent
                                live: root.opened && tile.primaryToplevel !== null
                                captureSource: tile.primaryToplevel ? tile.primaryToplevel.wayland : null
                                paintCursor: false
                            }

                            Text {
                                textFormat: Text.PlainText
                                visible: !capture.hasContent
                                anchors.centerIn: parent
                                text: tile.toplevels.length === 0 ? "Empty" : "…"
                                color: Color.menu.text
                                opacity: 0.4
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                font.italic: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Util.alpha(Color.background, tile.selected ? 0 : 0.42)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }

                                }

                            }

                            // Bottom title bar, over the thumbnail rather than pushing it
                            // smaller — same treatment a real window switcher uses.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Style.space(30)
                                color: Util.alpha(Color.menu.background, 0.85)

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.spacing.sm
                                    anchors.rightMargin: Style.spacing.sm
                                    spacing: Style.spacing.sm

                                    Text {
                                        textFormat: Text.PlainText
                                        text: (tile.modelData === 10 ? "0" : String(tile.modelData))
                                        color: tile.selected ? Color.accent : Color.menu.text
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.body
                                        font.letterSpacing: Style.headerTracking
                                    }

                                    Text {
                                        textFormat: Text.PlainText
                                        width: parent.width - Style.space(50)
                                        text: tile.primaryToplevel ? (tile.primaryToplevel.title || "") : (tile.focused ? "Current" : "")
                                        color: Color.menu.text
                                        opacity: 0.75
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        textFormat: Text.PlainText
                                        visible: tile.toplevels.length > 1
                                        text: "+" + (tile.toplevels.length - 1)
                                        color: Color.menu.text
                                        opacity: 0.5
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                    }

                                }

                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = tile.index
                                onClicked: root.focusAndClose(tile.modelData)
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }

                            }

                        }

                    }

                }

            }

        }

    }

}
