pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
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
    // meters, per-app binds and lane reads only exist while the panel shows
    readonly property bool live: panel.shown
    property int routingStreamId: -1
    // lane fader positions by lane name: stream keeps music a bed under voice, chill lets it lead
    readonly property var presets: [{
        "label": "STREAM",
        "faders": {
            "media": 0.55,
            "voice": 1
        }
    }, {
        "label": "CHILL",
        "faders": {
            "media": 1,
            "voice": 0.85
        }
    }]
    readonly property real presetTolerance: 0.02
    readonly property bool deafened: muted && micMuted
    readonly property string activePreset: {
        for (let i = 0; i < presets.length; i++) if (presetActive(presets[i])) {
            return presets[i].label;
        }
        return "";
    }

    function toggleMute() {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;

    }

    // undeafen unmutes both, not the prior state
    function toggleDeafen() {
        var target = !deafened;
        if (sink && sink.audio)
            sink.audio.muted = target;

        if (source && source.audio)
            source.audio.muted = target;

    }

    function laneKey(lane) {
        return lane.name.substring(Audio.lanePrefix.length);
    }

    function presetActive(preset) {
        var matched = false;
        for (let i = 0; i < Audio.lanes.length; i++) {
            let lane = Audio.lanes[i];
            let want = preset.faders[laneKey(lane)];
            if (want === undefined || !lane.audio)
                continue;

            if (Math.abs(lane.audio.volume - want) > presetTolerance)
                return false;

            matched = true;
        }
        return matched;
    }

    function presetApply(label) {
        var preset = presets.find((p) => {
            return p.label === label;
        });
        if (!preset)
            return ;

        for (let i = 0; i < Audio.lanes.length; i++) {
            let want = preset.faders[laneKey(Audio.lanes[i])];
            if (want !== undefined && Audio.lanes[i].audio)
                Audio.lanes[i].audio.volume = want;

        }
    }

    moduleName: "audio-io"
    visible: sink !== null
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    PwObjectTracker {
        objects: [root.sink, root.source].filter((n) => {
            return !!n;
        }).concat(root.live ? Audio.lanes.concat(Audio.appStreams, Audio.micListeners) : [])
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

                    Chip {
                        text: "EQ"
                        selected: Audio.eq !== null
                        onClicked: Audio.eqSet(Audio.eq === null)
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

                Meter {
                    width: content.width
                    node: root.sink
                    active: root.live
                }

                Flow {
                    width: content.width
                    spacing: Style.spacing.xs

                    Repeater {

                        model: ScriptModel {
                            values: Audio.sinks
                        }

                        delegate: Chip {
                            required property var modelData

                            text: Audio.deviceName(modelData)
                            selected: modelData === root.sink
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        }

                    }

                }

                PanelSeparator {
                    visible: Audio.lanes.length > 0
                }

                SectionHead {
                    text: "LANES"
                    visible: Audio.lanes.length > 0

                    ButtonGroup {
                        focusable: false
                        fontSize: Style.font.caption
                        options: root.presets.map((p) => {
                            return p.label;
                        })
                        value: root.activePreset
                        onChanged: function(v) {
                            root.presetApply(v);
                        }
                    }

                }

                Repeater {

                    model: ScriptModel {
                        values: Audio.lanes
                    }

                    delegate: LaneBlock {
                        host: root
                    }

                }

                PanelSeparator {
                }

                PanelSectionHeader {
                    text: "DIRECT"
                }

                Repeater {

                    model: ScriptModel {
                        values: Audio.appStreams.filter((s) => {
                            return !Audio.isLane(Audio.sinkOf(s));
                        })
                    }

                    delegate: StreamRow {
                        host: root
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
                        height: Style.row.control
                        verticalAlignment: Text.AlignVCenter
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

                PanelSeparator {
                }

                Rectangle {
                    width: content.width
                    height: Style.row.list
                    radius: Style.shape.data
                    color: root.deafened ? Util.alpha(Colors.urgent, 0.18) : (deafenHover.containsMouse ? Style.selectedFill : "transparent")

                    Row {
                        anchors.centerIn: parent
                        spacing: Style.spacing.xs

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
                            color: root.deafened ? Colors.urgent : Colors.menu.text
                            font.pixelSize: Style.font.icon
                            font.family: Style.font.iconFamily
                            layer.enabled: Style.fx.glow > 0 && root.deafened

                            layer.effect: Glow {
                                shadowColor: Colors.urgent
                            }

                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.deafened ? "Deafened, click to restore" : "Deafen"
                            color: root.deafened ? Colors.urgent : Colors.menu.text
                            font.pixelSize: Style.font.body
                            font.family: Style.font.family
                        }

                    }

                    MouseArea {
                        id: deafenHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDeafen()
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

                        // uwsm-app so it does not live in quickshell.service's cgroup
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
        color: Util.alpha(tint, 0.16)
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

    // the capture stream behind it exists only while active
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
            // dBFS: -9 hot, -3 close, -1 clipping
            color: Util.level(meter.levelDb, [-9, -3, -1])
        }

    }

    component Fader: Item {
        id: fader

        property var node: null
        property AudioIO host: null
        property string glyph: "\u{f057e}"
        property string mutedGlyph: "\u{f075f}"
        property string lane: ""
        property bool external: false
        property string obsLabel: ""
        readonly property real obsMul: external ? (Number(ObsProcess.inputVolumes[obsLabel]) || 0) : 0
        readonly property bool muted: external ? (ObsProcess.inputMutes[obsLabel] === true) : (node && node.audio ? node.audio.muted : false)
        readonly property real volume: external ? Math.min(1, obsMul) : (node && node.audio ? node.audio.volume : 0)
        // obs mul is linear amplitude: 20 log10 for dB, floored like Audio.dbText
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
            // optimistic, so the slider does not snap back before the next obs poll
            ObsProcess.inputVolumes = Util.mapSet(ObsProcess.inputVolumes, fader.obsLabel, value);
            ObsProcess.send({
                "cmd": "setInputVolume",
                "source": fader.obsLabel,
                "volume": value
            });
        }

        implicitHeight: slider.implicitHeight

        Caption {
            id: laneLabel

            visible: fader.lane !== ""
            width: visible ? Style.space(52) : 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: fader.lane
            color: fader.muted ? Colors.urgent : Colors.menu.text
            opacity: Style.emphasis.dim
        }

        Text {
            id: muteGlyph

            width: Style.space(24)
            anchors.left: laneLabel.right
            anchors.leftMargin: fader.lane !== "" ? Style.spacing.xs : 0
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

    // the obs fader is independent: what the stream hears, not what you hear
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
            lane: pair.obsHas ? "system" : ""
        }

        Fader {
            width: parent.width
            visible: pair.obsHas
            external: true
            host: pair.host
            lane: "OBS"
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
                id: routeChip

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.space(150))
                text: "> " + Audio.deviceName(stream.target)
                selected: stream.routing
                onClicked: stream.host.routingStreamId = stream.routing ? -1 : stream.node.id
            }

        }

        Fader {
            width: parent.width
            node: stream.node
            host: stream.host
        }

        Meter {
            width: parent.width
            node: stream.node
            active: stream.host !== null && stream.host.live
        }

        Flow {
            width: parent.width
            visible: stream.routing
            spacing: Style.spacing.xs

            Chip {
                text: "AUTO"
                onClicked: {
                    Audio.route(stream.node, null);
                    stream.host.routingStreamId = -1;
                }
            }

            Repeater {

                model: ScriptModel {
                    values: Audio.lanes.concat(Audio.sinks)
                }

                delegate: Chip {
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

    component LaneBlock: Column {
        id: lane

        required property var modelData
        property AudioIO host: null
        readonly property var node: modelData
        readonly property var outNode: Audio.nodes.find((n) => {
            return n.name === lane.node.name + ".out";
        }) || null
        readonly property var streams: Audio.appStreams.filter((s) => {
            return Audio.sinkOf(s) === lane.node;
        })
        // obs captures a lane under its key, capitalised, matching MUTE_SOURCES in obs-status.nu
        readonly property string obsLabel: {
            var k = root.laneKey(lane.node);
            return k ? k.charAt(0).toUpperCase() + k.slice(1) : "";
        }
        // read back from the filter graph, controls named in configs/desktop/pipewire/mod.nu
        property bool levelerOn: true
        property real targetLufs: NaN

        function refresh() {
            if (!readProc.running)
                readProc.running = true;

        }

        function levelerSet(on) {
            writeProc.command = ["pw-cli", "set-param", String(node.id), "Props", "{ params = [ \"amount:Mult\" " + (on ? 1 : 0) + " \"amount:Add\" " + (on ? 0 : 1) + " ] }"];
            writeProc.running = true;
        }

        function parse(text) {
            var values = ({
            });
            try {
                let props = JSON.parse(text || "[]")[0].info.params.Props || [];
                for (let i = 0; i < props.length; i++) {
                    let p = props[i].params;
                    if (!p)
                        continue;

                    for (let j = 0; j + 1 < p.length; j += 2) values[p[j]] = p[j + 1]
                }
            } catch (e) {
                return ;
            }
            levelerOn = values["amount:Mult"] > 0.5;
            targetLufs = Number(values["target:Target LUFS"]);
        }

        Component.onCompleted: {
            if (host && host.live) {
                refresh();
            }
        }
        width: parent ? parent.width : 0
        spacing: Style.spacing.xs

        Process {
            id: readProc

            command: ["pw-dump", String(lane.node.id)]

            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: lane.parse(text)
            }

        }

        Process {
            id: writeProc

            onExited: lane.refresh()
        }

        Connections {
            function onLiveChanged() {
                if (lane.host.live)
                    lane.refresh();

            }

            target: lane.host
        }

        SectionHead {
            text: lane.node.description

            // obs taps a lane's playback side, after the leveler and fader (configs/creating/obs)
            Tag {
                visible: Audio.isTappedByObs(lane.outNode)
                text: "OBS"
                tint: Colors.semantic.live
            }

            Chip {
                text: lane.levelerOn ? "LEVEL " + (isFinite(lane.targetLufs) ? lane.targetLufs.toFixed(0) + " LUFS" : "ON") : "LEVEL OFF"
                selected: lane.levelerOn
                onClicked: lane.levelerSet(!lane.levelerOn)
            }

        }

        ObsPair {
            width: parent.width
            node: lane.node
            host: lane.host
            obsLabel: lane.obsLabel
        }

        Row {
            readonly property real meterWidth: (width - inLabel.width - outLabel.width - spacing * 3) / 2

            width: parent.width
            spacing: Style.spacing.xs

            Caption {
                id: inLabel

                text: "IN"
                opacity: Style.emphasis.dim
                anchors.verticalCenter: parent.verticalCenter
            }

            Meter {
                width: parent.meterWidth
                anchors.verticalCenter: parent.verticalCenter
                node: lane.node
                active: lane.host.live
            }

            Caption {
                id: outLabel

                text: "OUT"
                opacity: Style.emphasis.dim
                anchors.verticalCenter: parent.verticalCenter
            }

            Meter {
                width: parent.meterWidth
                anchors.verticalCenter: parent.verticalCenter
                node: lane.outNode
                active: lane.host.live
            }

        }

        Repeater {

            model: ScriptModel {
                values: lane.streams
            }

            delegate: StreamRow {
                host: lane.host
            }

        }

    }

}
