// Native replacement for wlogout, bound to Super+Shift+E. Actions are
// immediate; the key letters are l/e/h/s/r.
// Lock shells out to `loginctl lock-session`, which hypridle's `lock_cmd`
// (configs/hyprland/hypridle.conf, hyprlock) answers.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// wlogout's own layout used `pkill Hyprland` for logout; `hyprctl dispatch
// exit` is the documented, non-SIGKILL equivalent (see
// configs/wlogout/layout).
Item {
    id: root

    property bool opened: false
    property int selectedIndex: 0
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    // Glyph codepoints resolved to their glyph names via fontTools against
    // 0xProto Nerd Font before use.
    readonly property var actions: [{
        "id": "lock",
        "label": "Lock",
        "icon": "\u{f023}",
        "destructive": false,
        "cmd": ["loginctl", "lock-session"]
    }, {
        "id": "exit",
        "label": "Exit",
        "icon": "\u{f08b}",
        "destructive": false,
        // Terminate this session directly instead of asking Hyprland to exit.
        // The latter is compositor-specific and was the reason Exit appeared
        // to do nothing in non-Hyprland/session-manager paths.
        "cmd": ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]
    }, {
        "id": "suspend",
        "label": "Suspend",
        "icon": "\u{f04b2}",
        "destructive": false,
        "cmd": ["systemctl", "suspend"]
    }, {
        "id": "shutdown",
        "label": "Shutdown",
        "icon": "\u{f011}",
        "destructive": false,
        "cmd": ["systemctl", "poweroff"]
    }, {
        "id": "reboot",
        "label": "Reboot",
        "icon": "\u{f0709}",
        "destructive": false,
        "cmd": ["systemctl", "reboot"]
    }]

    function open() {
        root.selectedIndex = 0;
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

    function activate(index) {
        if (index < 0 || index >= root.actions.length)
            return ;

        root.selectedIndex = index;
        root.runSelected();
    }

    function runSelected() {
        var action = root.actions[root.selectedIndex];
        if (!action)
            return ;

        Quickshell.execDetached(action.cmd);
        root.close();
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

        target: "powermenu"
    }

    PanelWindow {
        id: panel

        visible: root.opened
        color: "transparent"
        WlrLayershell.namespace: "quickshell-powermenu"
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

            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.selectedIndex = Math.min(root.actions.length - 1, root.selectedIndex + 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activate(root.selectedIndex);
                    event.accepted = true;
                } else {
                    var key = String.fromCharCode(event.key).toLowerCase();
                    var shortcuts = {
                        "l": 0,
                        "e": 1,
                        "h": 2,
                        "s": 3,
                        "r": 4
                    };
                    if (shortcuts[key] !== undefined) {
                        root.activate(shortcuts[key]);
                        event.accepted = true;
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: Style.spacing.huge

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spacing.md

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "SESSION"
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                        font.bold: true
                        font.letterSpacing: Style.headerTracking
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.userName
                        color: Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                    }

                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spacing.lg

                    Repeater {
                        model: root.actions

                        BorderSurface {
                            id: tile

                            required property var modelData
                            required property int index
                            readonly property bool selected: index === root.selectedIndex
                            readonly property color tint: Color.accent

                            width: Style.space(132)
                            height: Style.space(132)
                            radius: Style.cornerRadius
                            // Through the shared state engine, so every tile uses the same
                            // hover and selected colors rather than an action-specific ladder.
                            color: selected ? Style.selectedFillFor(Color.menu.text, tint) : Style.normalFillFor(Color.menu.text, tint)
                            borderSpec: Border.controlSpec(selected ? "selected" : "normal", Color.menu.text, tint)

                            Column {
                                anchors.centerIn: parent
                                spacing: Style.spacing.sm

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.icon
                                    color: tile.selected ? tile.tint : Color.menu.text
                                    font.family: Style.font.iconFamily
                                    font.pixelSize: Style.font.displayLarge
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.label
                                    color: tile.selected ? tile.tint : Color.menu.text
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: Style.headerTracking
                                }

                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = tile.index
                                onClicked: root.activate(tile.index)
                            }

                        }

                    }

                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    // Words, not arrow glyphs. U+2190..2193 and U+21B5 are NOT in
                    // 0xProto Nerd Font (checked with fontTools), so Qt silently
                    // substituted them from some other installed family and they
                    // rendered as dashes. U+00B7 is present and is used as the
                    // separator.
                    visible: false
                    text: ""
                    opacity: 0
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: Style.headerTracking
                }

            }

        }

    }

}
