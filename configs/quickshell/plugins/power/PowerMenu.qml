// Native replacement for wlogout, bound to Super+Shift+E.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// wlogout's own layout used `pkill Hyprland` for logout; `hyprctl dispatch exit` is the documented, non-SIGKILL equivalent (see configs/wlogout/layout).
Item {
    id: root

    property bool opened: false
    property int selectedIndex: 0
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    // Decorative hotkey badges, indexed to match the shortcut map in the key handler.
    readonly property var hotkeys: ["L", "E", "H", "S", "R"]
    // Glyph codepoints resolved to their glyph names via fontTools against 0xProto Nerd Font before use.
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

                // Terminal-window title strip spanning the action row: prompt, SESSION, blinking caret, user handle, decorative chrome, hard accent rule.
                Item {
                    width: actionRow.width
                    implicitHeight: titleRow.implicitHeight + Style.spacing.sm + titleRule.height
                    height: implicitHeight

                    Row {
                        id: titleRow
                        anchors.left: parent.left
                        anchors.top: parent.top
                        spacing: Style.spacing.sm

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: ">"
                            color: Color.accent
                            opacity: Style.emphasis.dim
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "SESSION"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            font.bold: true
                            font.letterSpacing: Style.headerTracking
                            // Accent neon bloom on the title.
                            layer.enabled: Style.fx.glow > 0
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Style.fx.glowColor
                                shadowBlur: 1.0
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                                blurMax: Style.fx.glowRadius
                                autoPaddingEnabled: true
                            }
                        }

                        // Blinking block caret, terminal prompt style.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "_"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            layer.enabled: Style.fx.glow > 0
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Style.fx.glowColor
                                shadowBlur: 1.0
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                                blurMax: Style.fx.glowRadius
                                autoPaddingEnabled: true
                            }
                            SequentialAnimation on opacity {
                                running: root.opened
                                loops: Animation.Infinite
                                PropertyAnimation { to: 1; duration: 0 }
                                PauseAnimation { duration: 530 }
                                PropertyAnimation { to: 0; duration: 0 }
                                PauseAnimation { duration: 530 }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            visible: root.userName.length > 0
                            text: "@" + root.userName
                            color: Color.menu.text
                            opacity: Style.emphasis.faint
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                        }
                    }

                    // Decorative window chrome glyphs, non-interactive.
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: titleRow.verticalCenter
                        textFormat: Text.PlainText
                        text: "[- o x]"
                        color: Color.accent
                        opacity: Style.emphasis.faint
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.letterSpacing: Style.headerTracking
                    }

                    // Hard accent rule under the title.
                    Rectangle {
                        id: titleRule
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: titleRow.bottom
                        anchors.topMargin: Style.spacing.sm
                        height: Math.max(1, Style.space(1))
                        color: Util.alpha(Color.accent, 0.8)
                    }
                }

                Row {
                    id: actionRow
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
                            // State fill tinted onto the opaque menu surface; a bare translucent fill let whatever sat under the scrim read through the tiles.
                            color: Qt.tint(Color.menu.background, selected ? Style.selectedFillFor(Color.menu.text, tint) : Style.normalFillFor(Color.menu.text, tint))
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
                                    // Bloom the icon of the focused action.
                                    layer.enabled: tile.selected && Style.fx.glow > 0
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: Style.fx.glowColor
                                        shadowBlur: 1.0
                                        shadowVerticalOffset: 0
                                        shadowHorizontalOffset: 0
                                        blurMax: Style.fx.glowRadius
                                        autoPaddingEnabled: true
                                    }
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

                            // Corner hotkey badge, HUD-grid style.
                            Text {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.topMargin: Style.spacing.sm
                                anchors.leftMargin: Style.spacing.sm
                                textFormat: Text.PlainText
                                text: "[" + (root.hotkeys[tile.index] || "") + "]"
                                color: tile.selected ? tile.tint : Color.menu.text
                                opacity: tile.selected ? Style.emphasis.strong : Style.emphasis.faint
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                font.letterSpacing: Style.headerTracking
                            }

                            // HUD reticle on the focused action.
                            HudFrame { visible: tile.selected && Style.fx.brackets }

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

                // Console command legend: the same hotkeys the key handler accepts.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: "[L] LOCK    [E] EXIT    [H] SUSPEND    [S] SHUTDOWN    [R] REBOOT"
                    color: Color.menu.text
                    opacity: Style.emphasis.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: Style.headerTracking
                }

            }

            // CRT scanline overlay across the session menu.
            Scanlines {}

        }

    }

}
