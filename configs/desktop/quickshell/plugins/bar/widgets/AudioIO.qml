pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source && source.audio ? source.audio.muted : true
    readonly property bool live: panel.shown
    property int routingStreamId: -1
    readonly property bool deafened: muted && micMuted
    function toggleMute() {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;

    }

    function toggleMicMute() {
        if (source && source.audio)
            source.audio.muted = !source.audio.muted;

    }

    function toggleDeafen() {
        var target = !deafened;
        if (sink && sink.audio)
            sink.audio.muted = target;

        if (source && source.audio)
            source.audio.muted = target;

    }

    moduleName: "audio-io"
    visible: sink !== null
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    PwObjectTracker {
        objects: [root.sink, root.source].filter((n) => {
            return !!n;
        }).concat(root.live ? Audio.appStreams.concat(Audio.loopbackOuts, Audio.micListeners, Audio.sinks) : [])
    }

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: Audio.volumeIcon(root.volume, root.muted)
        tooltipText: root.muted ? "Muted" : Math.round(root.volume * 100) + "%  " + Audio.dbText(root.volume) + " dB"
        onPressed: function(b) {
            if (b === Qt.MiddleButton)
                root.toggleMute();

        }
        onWheelMoved: function(delta) {
            Audio.nudge(root.sink, delta);
        }
        onEntered: {
            if (root.bar) {
                root.bar.hoverOpen(root.moduleName);
            }
        }
        onExited: {
            if (root.bar) {
                root.bar.hoverTriggerExit(root.moduleName);
            }
        }
    }

    HoverPanel {
        id: panel

        bar: root.bar
        moduleName: root.moduleName
        anchorWidget: root
        title: "AUDIO"
        implicitWidth: Style.panelWidth.wide
        implicitHeight: Math.min(content.implicitHeight, maxBodyHeight) + padding * 2 + titleInset
        onShownChanged: {
            if (!shown) {
                root.routingStreamId = -1;
            }
        }

        Flickable {
            width: parent.width
            height: Math.min(content.implicitHeight, panel.maxBodyHeight)
            contentWidth: width
            contentHeight: content.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: content

                width: parent.width
                spacing: Style.spacing.sm

                SectionHead {
                    text: "OUTPUT"

                    Tag {
                        visible: Audio.isTappedByObs(root.sink)
                        text: "OBS"
                        tint: Colors.semantic.live
                    }

                }

                Hero {
                    value: String(Math.round(root.volume * 100))
                    unit: "%"
                    color: root.muted ? Colors.urgent : Colors.accent
                }

                Fader {
                    width: content.width
                    node: root.sink
                    host: root
                    glyph: Audio.volumeIcon(root.volume, false)
                }

                Item {
                    width: content.width
                    visible: ObsProcess.connected || ObsProcess.listening
                    implicitHeight: hearGroup.implicitHeight

                    Caption {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "HEAR"
                        opacity: Style.emphasis.dim
                    }

                    ButtonGroup {
                        id: hearGroup

                        anchors.right: parent.right
                        spacing: Style.spacing.xs
                        fontSize: Style.font.caption
                        options: [{
                            "value": "me",
                            "label": "System"
                        }, {
                            "value": "obs",
                            "label": "OBS output"
                        }]
                        value: ObsProcess.listening ? "obs" : "me"
                        onChanged: function(v) {
                            ObsProcess.listenSet(v === "obs");
                        }
                    }

                }

                Flow {
                    width: content.width
                    spacing: Style.spacing.xs

                    Repeater {

                        model: ScriptModel {
                            values: Audio.sinks
                        }

                        delegate: Chip {
                            focusable: true
                            required property var modelData

                            text: Audio.deviceName(modelData)
                            selected: modelData === root.sink
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        }

                    }

                }

                PanelSeparator {
                }

                SectionHead {
                    text: "MICROPHONE"

                    Tag {
                        visible: Audio.isTappedByObs(root.source)
                        text: "OBS"
                        tint: Colors.semantic.live
                    }

                }

                ObsPair {
                    width: content.width
                    node: root.source
                    host: root
                    glyph: "\u{f036c}"
                    mutedGlyph: "\u{f036d}"
                    obsLabel: "Mic"
                }

                Meter {
                    width: content.width
                    node: root.source
                    active: root.live
                }

                Flow {
                    width: content.width
                    spacing: Style.spacing.xs

                    Repeater {

                        model: ScriptModel {
                            values: Audio.sources
                        }

                        delegate: Chip {
                            focusable: true
                            required property var modelData

                            text: Audio.deviceName(modelData)
                            selected: modelData === root.source
                            onClicked: Pipewire.preferredDefaultAudioSource = modelData
                        }

                    }

                }

                Flow {
                    width: content.width
                    visible: Audio.micListeners.length > 0
                    spacing: Style.spacing.xs

                    Caption {
                        text: "HEARD BY"
                        opacity: Style.emphasis.dim
                    }

                    Repeater {

                        model: ScriptModel {
                            values: Audio.micListeners
                        }

                        delegate: Tag {
                            required property var modelData

                            text: Audio.appName(modelData)
                            tint: Audio.isObs(modelData) ? Colors.semantic.live : Colors.semantic.speaking
                        }

                    }

                }

                Column {
                    width: content.width
                    spacing: Style.spacing.sm
                    visible: Audio.appStreams.length > 0

                    PanelSeparator {
                    }

                    PanelSectionHeader {
                        text: "APPS"
                    }

                    Repeater {

                        model: ScriptModel {
                            values: Audio.appStreams
                        }

                        delegate: StreamRow {
                            host: root
                        }

                    }

                }

                PanelSeparator {
                }

                Row {
                    width: content.width
                    spacing: Style.spacing.sm

                    PanelRow {
                        width: (parent.width - parent.spacing) / 2
                        centered: true
                        glyph: root.micMuted ? "\u{f036d}" : "\u{f036c}"
                        label: root.micMuted ? "Muted" : "Mute"
                        on: root.micMuted
                        onActivated: root.toggleMicMute()
                    }

                    PanelRow {
                        width: (parent.width - parent.spacing) / 2
                        centered: true
                        glyph: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
                        label: root.deafened ? "Deafened" : "Deafen"
                        on: root.deafened
                        onActivated: root.toggleDeafen()
                    }

                }

                PanelSeparator {
                }

                PanelRow {
                    width: parent.width
                    glyph: "\u{f1049}"
                    label: "Patchbay (qpwgraph)"
                    onActivated: {
                        if (root.bar)
                            root.bar.closePanel(root.moduleName);

                        Quickshell.execDetached(["uwsm-app", "--", "qpwgraph"]);
                    }
                }

            }

        }

    }

    component Caption: Text {
        textFormat: Text.PlainText
        color: Colors.menu.text
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }

    component Tag: Rectangle {
        id: tag

        property string text: ""
        property color tint: Colors.accent

        implicitWidth: tagLabel.implicitWidth + Style.spacing.sm * 2
        implicitHeight: tagLabel.implicitHeight + Style.spacing.xxs * 2
        radius: Style.shape.data
        color: Util.alpha(tint, Style.tintFillAlpha)
        border.color: Util.alpha(tint, 0.6)
        border.width: Style.spacing.hair

        Text {
            id: tagLabel

            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: tag.text
            color: tag.tint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.labelTracking
        }

    }

    component SectionHead: Item {
        id: head

        property string text: ""
        default property alias extras: extrasRow.data

        width: parent ? parent.width : 0
        implicitHeight: Math.max(headTitle.implicitHeight, extrasRow.implicitHeight)

        PanelSectionHeader {
            id: headTitle

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: head.text
        }

        Row {
            id: extrasRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
        }

    }

    component Meter: Item {
        id: meter

        property var node: null
        property bool active: false
        readonly property real levelDb: Audio.db(monitor.peak)

        implicitHeight: Style.spacing.xs

        PwNodePeakMonitor {
            id: monitor

            node: meter.node
            enabled: meter.active && meter.node !== null
        }

        BarGauge {
            anchors.fill: parent
            segments: 32
            value: meter.active ? Audio.meterPosition(monitor.peak) : 0
            color: Util.level(meter.levelDb, [-9, -3, -1])
        }

    }

    component Fader: Item {
        id: fader

        property var node: null
        property AudioIO host: null
        property string glyph: "\u{f057e}"
        property string mutedGlyph: "\u{f075f}"
        property string caption: ""
        property bool external: false
        property string obsLabel: ""
        readonly property real obsMul: external ? (Number(ObsProcess.inputVolumes[obsLabel]) || 0) : 0
        readonly property bool muted: external ? (ObsProcess.inputMutes[obsLabel] === true) : (node && node.audio ? node.audio.muted : false)
        readonly property real volume: external ? Math.min(1, obsMul) : (node && node.audio ? node.audio.volume : 0)
        readonly property string readoutText: muted ? "MUTE" : external ? (obsMul > 0 ? (20 * Math.log(obsMul) / Math.LN10).toFixed(1) + " dB" : "-inf") : Audio.dbText(volume) + " dB"

        function toggleMute() {
            if (external) {
                ObsProcess.send({
                    "cmd": "toggleMute",
                    "source": fader.obsLabel
                });
                return ;
            }
            if (node && node.audio)
                node.audio.muted = !node.audio.muted;

        }

        function setExternal(value) {
            ObsProcess.inputVolumes = Util.mapSet(ObsProcess.inputVolumes, fader.obsLabel, value);
            ObsProcess.send({
                "cmd": "setInputVolume",
                "source": fader.obsLabel,
                "volume": value
            });
        }

        implicitHeight: slider.implicitHeight

        Caption {
            id: captionLabel

            visible: fader.caption !== ""
            width: visible ? Style.space(52) : 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: fader.caption
            color: fader.muted ? Colors.urgent : Colors.menu.text
            opacity: Style.emphasis.dim
        }

        Text {
            id: muteGlyph

            width: Style.space(24)
            anchors.left: captionLabel.right
            anchors.leftMargin: fader.caption !== "" ? Style.spacing.xs : 0
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: fader.muted ? fader.mutedGlyph : fader.glyph
            color: fader.muted ? Colors.urgent : Colors.menu.text
            font.family: Style.font.iconFamily
            font.pixelSize: Style.font.icon

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: fader.toggleMute()
            }

        }

        Slider {
            id: slider

            anchors.left: muteGlyph.right
            anchors.right: readout.left
            anchors.leftMargin: Style.spacing.sm
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            bar: fader.host ? fader.host.bar : null
            value: fader.volume
            fillColor: fader.muted ? Colors.urgent : (bar ? bar.barForeground : Colors.foreground)
            onMoved: function(v) {
                if (fader.external)
                    fader.setExternal(v);
                else if (fader.node && fader.node.audio)
                    fader.node.audio.volume = v;
            }
            onRightClicked: fader.toggleMute()
        }

        Caption {
            id: readout

            width: Style.space(58)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: fader.readoutText
            color: fader.muted ? Colors.urgent : Colors.menu.text
        }

    }

    component ObsPair: Column {
        id: pair

        property var node: null
        property AudioIO host: null
        property string glyph: "\u{f057e}"
        property string mutedGlyph: "\u{f075f}"
        property string obsLabel: ""
        readonly property bool obsHas: ObsProcess.connected && pair.obsLabel !== "" && ObsProcess.inputVolumes[pair.obsLabel] !== undefined

        width: parent ? parent.width : 0
        spacing: Style.spacing.xs

        Fader {
            width: parent.width
            node: pair.node
            host: pair.host
            glyph: pair.glyph
            mutedGlyph: pair.mutedGlyph
            caption: pair.obsHas ? "system" : ""
        }

        Fader {
            width: parent.width
            visible: pair.obsHas
            external: true
            host: pair.host
            caption: "OBS"
            glyph: pair.glyph
            mutedGlyph: pair.mutedGlyph
            obsLabel: pair.obsLabel
        }

    }

    component StreamRow: Column {
        id: stream

        required property var modelData
        property AudioIO host: null
        readonly property var node: modelData
        readonly property var target: Audio.sinkOf(node)
        readonly property bool onStream: Audio.isTappedByObs(node)
        readonly property bool routing: host !== null && host.routingStreamId === node.id

        width: parent ? parent.width : 0
        spacing: Style.spacing.xs

        Item {
            width: parent.width
            implicitHeight: Math.max(appIcon.height, routeChip.implicitHeight)

            IconImage {
                id: appIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Style.font.icon + Style.spacing.sm
                source: Audio.appIcon(stream.node)
            }

            Text {
                anchors.left: appIcon.right
                anchors.leftMargin: Style.spacing.sm
                anchors.right: tags.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: Audio.appName(stream.node)
                color: Colors.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Row {
                id: tags

                anchors.right: routeChip.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Tag {
                    visible: stream.onStream
                    text: "OBS"
                    tint: Colors.semantic.live
                }

            }

            Chip {
                focusable: true
                id: routeChip

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.space(150))
                text: "> " + Audio.deviceName(stream.target)
                selected: stream.routing
                onClicked: stream.host.routingStreamId = stream.routing ? -1 : stream.node.id
            }

        }

        ObsPair {
            width: parent.width
            node: Audio.levelOf(stream.node)
            host: stream.host
            obsLabel: Audio.obsInputOf(stream.node)
        }

        Flow {
            width: parent.width
            visible: stream.routing
            spacing: Style.spacing.xs

            Chip {
                focusable: true
                text: "AUTO"
                onClicked: {
                    Audio.route(stream.node, null);
                    stream.host.routingStreamId = -1;
                }
            }

            Repeater {

                model: ScriptModel {
                    values: Audio.sinks
                }

                delegate: Chip {
                    focusable: true
                    required property var modelData

                    text: Audio.deviceName(modelData)
                    selected: stream.target === modelData
                    onClicked: {
                        Audio.route(stream.node, modelData);
                        stream.host.routingStreamId = -1;
                    }
                }

            }

        }

    }

}
