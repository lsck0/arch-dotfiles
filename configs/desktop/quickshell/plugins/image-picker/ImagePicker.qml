pragma ComponentBehavior: Bound
import "ImagePickerModel.js" as ImagePickerModel
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    readonly property string pluginDir: Paths.plugin("image-picker")
    property string themeDir: Paths.themes
    property int mode: 0
    property var modeNames: ["Wallpapers", "Themes"]
    property string imageRows: ""
    property string loadedImageRows: ""
    property string selectionFile: ""
    property string selectedImage: ""
    property int selectedIndex: 0
    property bool imagesLoaded: false
    property bool opened: false
    property bool showLabels: false
    property bool filterable: false
    property bool layoutSettled: false
    property bool requestActive: false
    property int requestSerial: 0
    property int applySerial: 0
    property string doneFile: ""
    property string filterText: ""
    property var filterMatches: []
    property var filterPositions: []
    property int filteredCount: 0
    property ProcessQueue releaseQueue: ProcessQueue {
        onRunItem: function (path) {
            releaseProc.command = ["bash", "-c", ": > " + Util.shellQuote(path)];
            releaseProc.running = true;
        }
    }
    property var imageArray: []
    property color dimColor: Colors.background
    property color foreground: Colors.imagePicker.text
    property color scrim: Colors.imagePicker.scrim
    property color selectedBorder: Colors.imagePicker.selectedBorder
    property color unselectedBorder: Colors.imagePicker.unselectedBorder
    property int expandedWidth: Style.space(768)
    property int expandedHeight: Style.space(475)
    property int sliceWidth: Style.space(108)
    property int sliceHeight: Style.space(432)
    property int sliceSpacing: -Style.space(30)
    property int skewOffset: Style.space(28)
    readonly property int sliceCount: 13
    readonly property int nearbyRange: 16
    readonly property bool showPalette: mode === 0
    readonly property int paletteHeight: showPalette ? Style.space(40) : 0
    property int bottomChromeHeight: paletteHeight + (showLabels ? (filterable ? Style.space(104) : Style.space(74)) : (filterable ? Style.space(60) : Style.space(30)))
    property var preview: null
    readonly property int quantizeDepth: 3
    readonly property int quantizeSize: 64

    function rebuildFilterCache() {
        var matches = [];
        var positions = [];
        var count = 0;
        var needle = String(filterText || "").toLowerCase();
        for (let i = 0; i < imageArray.length; i++) {
            const image = imageArray[i];
            const path = String(image.filePath || "");
            const matched = !needle || nameForPath(path).toLowerCase().indexOf(needle) !== -1 || labelForPath(path).toLowerCase().indexOf(needle) !== -1 || labelForImage(image).toLowerCase().indexOf(needle) !== -1;
            matches.push(matched);
            positions.push(matched ? count++ : -1);
        }
        filterMatches = matches;
        filterPositions = positions;
        filteredCount = count;
    }

    function scriptPath(name) {
        return root.pluginDir + "/" + name;
    }

    function focusPicker() {
        if (root.opened && root.imagesLoaded && root.layoutSettled)
            carousel.forceActiveFocus();

    }

    function revealWhenSettled(serial) {
        Qt.callLater(function() {
            if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) {
                root.layoutSettled = true;
                root.focusPicker();
            }
        });
    }

    function currentPath() {
        if (imageArray.length === 0 || !itemMatches(selectedIndex))
            return "";

        return imageArray[selectedIndex].filePath;
    }

    function nameForPath(path) {
        return ImagePickerModel.nameForPath(path);
    }

    function labelForPath(path) {
        return ImagePickerModel.labelForPath(path);
    }

    function labelForImage(image) {
        return ImagePickerModel.labelForImage(image);
    }

    function currentLabel() {
        if (imageArray.length === 0 || !itemMatches(selectedIndex))
            return filterText ? "No matches" : "";

        return labelForImage(imageArray[selectedIndex]);
    }

    function itemMatches(index) {
        return index >= 0 && index < filterMatches.length ? filterMatches[index] : false;
    }

    function firstMatchingIndex() {
        for (let i = 0; i < filterMatches.length; i++) {
            if (filterMatches[i])
                return i;

        }
        return -1;
    }

    function filteredPosition(index) {
        return index >= 0 && index < filterPositions.length ? filterPositions[index] : -1;
    }

    function selectedFilteredPosition() {
        var position = filteredPosition(selectedIndex);
        return position >= 0 ? position : 0;
    }

    function select(index, immediate) {
        if (imageArray.length === 0)
            return ;

        if (index < 0)
            index = 0;
        else if (index >= imageArray.length)
            index = imageArray.length - 1;
        if (!itemMatches(index))
            return ;

        if (index === selectedIndex && immediate !== true)
            return ;

        selectedIndex = index;
    }

    function selectAdjacent(direction) {
        var count = imageArray.length;
        if (count === 0)
            return ;

        var index = selectedIndex;
        for (let i = 0; i < count; i++) {
            index = (index + direction + count) % count;
            if (itemMatches(index)) {
                select(index);
                return ;
            }
        }
    }

    function updateFilter(nextFilterText) {
        filterText = nextFilterText;
        rebuildFilterCache();
        if (!itemMatches(selectedIndex)) {
            const first = firstMatchingIndex();
            if (first >= 0)
                selectedIndex = first;

        }
    }

    function finishDoneFile(path) {
        if (!path)
            return ;

        releaseQueue.enqueue(path);
    }

    function applySelected() {
        var path = currentPath();
        if (!path || !selectionFile) {
            cancel();
            return ;
        }
        var activeSelectionFile = selectionFile;
        var activeDoneFile = doneFile;
        applySerial = requestSerial;
        requestActive = false;
        selectionFile = "";
        doneFile = "";
        applyProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(path) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)];
        applyProc.running = true;
    }

    function cancel() {
        if (requestActive)
            finishDoneFile(doneFile);

        requestActive = false;
        selectionFile = "";
        doneFile = "";
        root.opened = false;
    }

    function loadRows(rows, reveal) {
        var newImages = ImagePickerModel.loadRows(rows);
        root.loadedImageRows = rows;
        root.selectedIndex = root.indexForSelectedImage(newImages);
        root.imageArray = newImages;
        root.rebuildFilterCache();
        root.imagesLoaded = true;
        if (reveal !== false) {
            root.opened = true;
            root.revealWhenSettled(root.requestSerial);
        }
    }

    function openSelector(nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
        if (requestActive && doneFile && doneFile !== nextDoneFile)
            finishDoneFile(doneFile);

        requestSerial += 1;
        imageRows = nextImageRows;
        selectedImage = nextSelectedImage;
        selectionFile = nextSelectionFile;
        doneFile = nextDoneFile;
        requestActive = !!doneFile;
        showLabels = nextShowLabels === true || nextShowLabels === "true";
        filterable = nextFilterable === true || nextFilterable === "true";
        filterText = "";
        layoutSettled = false;
        if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
            root.rebuildFilterCache();
            root.select(root.selectedImageIndex(), true);
            imagesLoaded = true;
            opened = true;
            root.revealWhenSettled(requestSerial);
            return ;
        }
        if (imageRows) {
            const rowsToLoad = imageRows;
            const rowsSerial = requestSerial;
            imageArray = [];
            selectedIndex = 0;
            imagesLoaded = true;
            opened = true;
            Qt.callLater(function() {
                if (rowsSerial === root.requestSerial)
                    root.loadRows(rowsToLoad, true);

            });
            return ;
        }
        imageArray = [];
        selectedIndex = 0;
        imagesLoaded = false;
        opened = false;
        startImageScan(requestSerial);
    }

    function startImageScan(serial) {
        if (loadImagesProc.running) {
            loadImagesProc.queuedSerial = serial;
            return ;
        }
        loadImagesProc.activeSerial = serial;
        loadImagesProc.queuedSerial = 0;
        loadImagesProc.command = root.mode === 1 ? [root.scriptPath("list.nu"), "themes", root.themeDir, Paths.wallpaperList] : [root.scriptPath("list.nu"), Paths.wallpaperList];
        loadImagesProc.running = true;
    }

    function switchMode() {
        var next = root.mode === 1 ? 0 : 1;
        root.mode = next;
        root.filterText = "";
        root.selectedImage = "";
        root.imageArray = [];
        root.selectedIndex = 0;
        root.imagesLoaded = false;
        root.layoutSettled = false;
        root.requestSerial += 1;
        root.startImageScan(root.requestSerial);
    }

    function indexForSelectedImage(images) {
        return ImagePickerModel.indexForSelectedImage(images, selectedImage);
    }

    function selectedImageIndex() {
        return indexForSelectedImage(imageArray);
    }

    function open(args) {
        var tDirs = String(args.themeDir || themeDir);
        var rows = String(args.imageRows || "");
        var sel = String(args.selectedImage || selectedImage);
        var selFile = String(args.selectionFile || "");
        var doneF = String(args.doneFile || "");
        var labels = args.showLabels === true || args.showLabels === "true";
        var filter = args.filterable === true || args.filterable === "true";
        themeDir = tDirs;
        mode = args.mode === 1 ? 1 : 0;
        openSelector(rows, sel, selFile, doneF, labels, filter);
    }

    function close() {
        cancel();
    }

    onSelectedIndexChanged: {
        root.preview = null;
        quantizeDelay.restart();
    }
    onImageArrayChanged: quantizeDelay.restart()
    onOpenedChanged: {
        if (opened)
            return ;

        layoutSettled = false;
        quantizeDelay.stop();
        quantizer.source = "";
    }

    ColorQuantizer {
        id: quantizer

        depth: root.quantizeDepth
        rescaleSize: root.quantizeSize
        onColorsChanged: {
            try {
                const raw = ImagePickerModel.rawFromSwatches(quantizer.colors);
                root.preview = raw.special ? Colors.conditionPalette(raw) : null;
            } catch (e) {
                root.preview = null;
            }
        }
    }

    Timer {
        id: quantizeDelay

        interval: Style.motion.slow
        onTriggered: {
            var image = root.imageArray[root.selectedIndex];
            quantizer.source = root.opened && root.showPalette && image ? Util.fileUrl(image.thumbnailPath || image.filePath) : "";
        }
    }

    Timer {
        id: streamFlush

        interval: 120
        onTriggered: {
            if (loadImagesProc.activeSerial === root.requestSerial && loadImagesProc.streamBuffer.length > 0)
                root.loadRows(loadImagesProc.streamBuffer, true);

        }
    }

    Process {
        id: loadImagesProc

        property int activeSerial: 0
        property int queuedSerial: 0
        property string streamBuffer: ""

        onExited: {
            if (activeSerial === root.requestSerial && streamBuffer.length > 0)
                root.loadRows(streamBuffer, true);

            streamBuffer = "";
            var serial = queuedSerial;
            activeSerial = 0;
            queuedSerial = 0;
            if (serial > 0 && serial === root.requestSerial)
                root.startImageScan(serial);

        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (loadImagesProc.activeSerial !== root.requestSerial)
                    return ;

                if (!line)
                    return ;

                loadImagesProc.streamBuffer += line + "\n";
                streamFlush.restart();
            }
        }

    }

    Process {
        id: applyProc

        onExited: {
            if (root.applySerial === root.requestSerial)
                root.opened = false;

        }
    }

    Process {
        id: releaseProc

        onExited: root.releaseQueue.done()
    }

    BootIn {
        id: boot

        active: root.opened
        title: root.modeNames[root.mode] || ""
        span: Math.min(root.expandedWidth, root.expandedHeight) / 2
    }

    PanelWindow {
        visible: root.opened || boot.progress > 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell-image-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: root.scrim
            opacity: boot.progress
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.opened
            onClicked: root.cancel()
        }

        Item {
            visible: root.imagesLoaded && root.imageArray.length > 0 && (root.opened ? root.layoutSettled : boot.progress > 0)
            opacity: boot.progress
            width: Math.min(parent.width - Style.space(80), root.expandedWidth + root.sliceCount * (root.sliceWidth + root.sliceSpacing) + Style.space(40))
            height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight
            anchors.centerIn: parent

            MouseArea {
                anchors.fill: parent
                onClicked: {
                }
            }

            Item {
                id: carousel

                readonly property real itemStep: root.sliceWidth + root.sliceSpacing
                readonly property real previewX: (width - root.expandedWidth) / 2

                anchors.top: parent.top
                anchors.topMargin: Style.space(30)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.bottomChromeHeight
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.expandedWidth + root.sliceCount * (root.sliceWidth + root.sliceSpacing)
                clip: false
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        if (root.filterText)
                            root.updateFilter("");
                        else
                            root.cancel();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.applySelected();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (root.filterable)
                            root.updateFilter(root.filterText.slice(0, -1));

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
                        root.selectAdjacent(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                        root.selectAdjacent(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                        root.switchMode();
                        event.accepted = true;
                    } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        root.updateFilter(root.filterText + event.text);
                        event.accepted = true;
                    }
                }
                Component.onCompleted: forceActiveFocus()

                Repeater {
                    model: root.imageArray.length

                    delegate: Item {
                        id: item

                        required property int index
                        readonly property var imageData: root.imageArray[index]
                        readonly property string filePath: imageData ? imageData.filePath : ""
                        readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""
                        readonly property bool matched: root.itemMatches(index)
                        readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
                        readonly property bool selected: matched && index === root.selectedIndex
                        readonly property bool nearby: matched && Math.abs(relativeIndex) <= root.nearbyRange
                        property bool sourceActivated: nearby
                        readonly property real skAbs: Math.abs(root.skewOffset)
                        readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
                        readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
                        readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
                        readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

                        onNearbyChanged: {
                            if (nearby) {
                                sourceActivated = true;
                            }
                        }
                        visible: nearby
                        x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
                        width: selected ? root.expandedWidth : root.sliceWidth
                        height: selected ? root.expandedHeight : root.sliceHeight
                        y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
                        z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

                        Item {
                            id: maskShape

                            anchors.fill: parent
                            visible: false
                            layer.enabled: true

                            Shape {
                                anchors.fill: parent
                                antialiasing: true
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: "white"
                                    strokeColor: "transparent"
                                    startX: item.topLeft
                                    startY: 0

                                    PathLine {
                                        x: item.topRight
                                        y: 0
                                    }

                                    PathLine {
                                        x: item.bottomRight
                                        y: item.height
                                    }

                                    PathLine {
                                        x: item.bottomLeft
                                        y: item.height
                                    }

                                    PathLine {
                                        x: item.topLeft
                                        y: 0
                                    }

                                }

                            }

                        }

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.smooth: true

                            Image {
                                anchors.fill: parent
                                source: !item.sourceActivated ? "" : Util.fileUrl(item.thumbnailPath || item.filePath)
                                sourceSize.width: Math.ceil((item.selected ? root.expandedWidth : root.sliceWidth) * Screen.devicePixelRatio)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                            }

                            Image {
                                anchors.fill: parent
                                source: (item.selected && item.sourceActivated && item.filePath) ? Util.fileUrl(item.filePath) : ""
                                sourceSize.width: Math.ceil(root.expandedWidth * Screen.devicePixelRatio)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                smooth: true
                                opacity: status === Image.Ready ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Style.motion.base
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Style.motion.enter
                                    }

                                }

                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Util.alpha(root.dimColor, item.selected ? 0 : 0.42)
                            }

                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: maskShape
                                maskThresholdMin: 0.3
                                maskSpreadAtMin: 0.3
                            }

                        }

                        Shape {
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            layer.enabled: item.selected && Style.fx.glow > 0

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                                strokeWidth: item.selected ? Style.focusBorderWidth : Style.normalBorderWidth
                                startX: item.topLeft
                                startY: 0

                                PathLine {
                                    x: item.topRight
                                    y: 0
                                }

                                PathLine {
                                    x: item.bottomRight
                                    y: item.height
                                }

                                PathLine {
                                    x: item.bottomLeft
                                    y: item.height
                                }

                                PathLine {
                                    x: item.topLeft
                                    y: 0
                                }

                            }

                            layer.effect: Glow {
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: item.selected ? root.applySelected() : root.select(item.index)
                        }

                        Behavior on x {
                            enabled: root.layoutSettled

                            NumberAnimation {
                                duration: Style.motion.slow
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Style.motion.enter
                            }

                        }

                        Behavior on y {
                            enabled: root.layoutSettled

                            NumberAnimation {
                                duration: Style.motion.slow
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Style.motion.enter
                            }

                        }

                        Behavior on width {
                            enabled: root.layoutSettled

                            NumberAnimation {
                                duration: Style.motion.slow
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Style.motion.enter
                            }

                        }

                        Behavior on height {
                            enabled: root.layoutSettled

                            NumberAnimation {
                                duration: Style.motion.slow
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Style.motion.enter
                            }

                        }

                    }

                }

            }

            Row {
                id: paletteStrip

                visible: root.showPalette
                anchors.top: carousel.bottom
                anchors.topMargin: Style.spacing.sm
                anchors.horizontalCenter: carousel.horizontalCenter
                height: root.paletteHeight - Style.spacing.sm
                spacing: Style.spacing.sm

                Repeater {
                    model: [["bg", "background"], ["fg", "foreground"], ["acc", "accent"], ["acc2", "accent2"], ["urg", "urgent"]]

                    Column {
                        required property var modelData

                        spacing: Style.spacing.xxs

                        Rectangle {
                            width: Style.space(40)
                            height: Style.space(12)
                            radius: Style.shape.data
                            color: root.preview ? root.preview[parent.modelData[1]] : "transparent"
                            border.width: Style.normalBorderWidth
                            border.color: root.unselectedBorder
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            textFormat: Text.PlainText
                            text: parent.modelData[0]
                            color: Colors.textDim
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                        }

                    }

                }

                Text {
                    textFormat: Text.PlainText
                    text: root.preview ? ":: " + root.preview.verdict : ":: --"
                    color: !root.preview ? root.foreground : root.preview.verdict === "OK" ? Colors.okText : Colors.warnText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                }

            }

            BorderSurface {
                id: searchChip

                readonly property bool focused: root.opened
                readonly property bool hot: searchHover.hovered

                visible: root.filterable && root.filterText.length > 0
                anchors.top: root.showPalette ? paletteStrip.bottom : carousel.bottom
                anchors.topMargin: Style.spacing.md
                anchors.horizontalCenter: carousel.horizontalCenter
                width: Math.min(root.expandedWidth, Style.space(360))
                height: Style.space(38)
                radius: Style.shape.data
                color: Style.controlFill(focused, hot, root.foreground, root.selectedBorder)
                borderSpec: Border.controlSpec(focused ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, root.selectedBorder)

                HoverHandler {
                    id: searchHover
                }

                TapHandler {
                    onTapped: root.focusPicker()
                }

                OpticalGlyph {
                    id: searchIcon

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.sm
                    text: "\u{ea6d}" // cod-search
                    fontSize: Style.font.body
                    color: Util.alpha(root.foreground, root.filterText ? Style.emphasis.strong : Style.emphasis.dim)
                }

                Row {
                    id: queryRow

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: searchIcon.right
                    anchors.leftMargin: Style.spacing.xs
                    anchors.right: clearButton.left
                    anchors.rightMargin: Style.spacing.xs
                    spacing: Style.spacing.xxs

                    Text {

                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, queryRow.width - caret.width - queryRow.spacing)
                        textFormat: Text.PlainText
                        text: root.filterText || "filter by name"
                        color: root.filterText ? root.foreground : Colors.textDim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                    }

                    BlinkCaret {
                        id: caret

                        anchors.verticalCenter: parent.verticalCenter
                        prompt: true
                        size: Style.font.body
                        color: root.selectedBorder
                        running: root.opened
                    }

                }

                Item {
                    id: clearButton

                    visible: root.filterText.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.xs
                    width: Style.space(22)
                    height: Style.space(22)

                    OpticalGlyph {
                        anchors.centerIn: parent
                        text: "\u{f0156}" // md-close
                        fontSize: Style.font.caption
                        color: Util.alpha(root.foreground, clearHover.hovered ? Style.emphasis.strong : Style.emphasis.dim)
                    }

                    HoverHandler {
                        id: clearHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.updateFilter("");
                            carousel.forceActiveFocus();
                        }
                    }

                }

            }

            Text {
                textFormat: Text.PlainText
                visible: root.showLabels
                anchors.top: searchChip.visible ? searchChip.bottom : root.showPalette ? paletteStrip.bottom : carousel.bottom
                anchors.topMargin: Style.spacing.sm
                anchors.horizontalCenter: carousel.horizontalCenter
                width: root.expandedWidth
                text: root.currentLabel()
                color: root.foreground
                style: Text.Outline
                styleColor: Util.alpha(root.dimColor, 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Item {
                anchors.top: parent.top
                anchors.topMargin: Style.spacing.xs
                anchors.horizontalCenter: carousel.horizontalCenter
                width: root.expandedWidth
                height: Style.space(24)

                HudTitle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeNames[root.mode] || ""
                    typed: boot.typed
                    suffix: "[" + String(root.filteredCount) + "]"
                    color: root.selectedBorder
                    blinking: root.opened
                }

            }

            HudFrame {
                inset: boot.bracketInset
            }

        }

        Scanlines {
            flicker: true
        }

    }

}
