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

  component SlowMove: Behavior {
    NumberAnimation {
      duration: Style.motion.slow
      easing.type: Easing.BezierSpline
      easing.bezierCurve: Style.motion.enter
    }
  }

  readonly property string pluginDir: Paths.plugin("image-picker")
  readonly property string dot: Paths.bin("dot")
  property int mode: 0
  property var modeNames: ["Wallpapers", "Themes"]
  property string selectedImage: ""
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool layoutSettled: false
  readonly property bool ready: imagesLoaded && imageArray.length > 0 && (opened ? layoutSettled : true)
  property int requestSerial: 0
  readonly property string filterText: filterField.text
  property var filterMatches: []
  property var filterPositions: []
  property int filteredCount: 0
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
  property int bottomChromeHeight: paletteHeight + Style.space(104)
  property var preview: null
  readonly property int quantizeDepth: 3
  readonly property int quantizeSize: 64

  function rebuildFilterCache() {
    var matches = []
    var positions = []
    var count = 0
    var needle = String(filterText || "").toLowerCase()
    for (let i = 0; i < imageArray.length; i++) {
      const image = imageArray[i]
      const path = String(image.filePath || "")
      const matched = !needle || ImagePickerModel.nameForPath(path).toLowerCase().indexOf(needle) !== -1 || ImagePickerModel.labelForPath(path).toLowerCase().indexOf(needle) !== -1 || ImagePickerModel.labelForImage(image).toLowerCase().indexOf(needle) !== -1
      matches.push(matched)
      positions.push(matched ? count++ : -1)
    }
    filterMatches = matches
    filterPositions = positions
    filteredCount = count
  }

  function revealWhenSettled(serial) {
    Qt.callLater(function() {
      if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0)
        root.layoutSettled = true
    })
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function currentLabel() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return filterText ? "No matches" : ""
    return ImagePickerModel.labelForImage(imageArray[selectedIndex])
  }

  function itemMatches(index) {
    return index >= 0 && index < filterMatches.length ? filterMatches[index] : false
  }

  function firstMatchingIndex() {
    for (let i = 0; i < filterMatches.length; i++) {
      if (filterMatches[i]) return i
    }
    return -1
  }

  function filteredPosition(index) {
    return index >= 0 && index < filterPositions.length ? filterPositions[index] : -1
  }

  function selectedFilteredPosition() {
    var position = filteredPosition(selectedIndex)
    return position >= 0 ? position : 0
  }

  function select(index) {
    if (index >= 0 && index < imageArray.length && itemMatches(index)) selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return
    var index = selectedIndex
    for (let i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
    }
  }

  function applySelected() {
    var path = currentPath()
    if (path) Quickshell.execDetached([root.dot, "theme", path])
    root.cancel()
  }

  // a new serial drops the scan still streaming, so its late rows cannot reopen the picker
  function cancel() {
    root.requestSerial += 1
    root.opened = false
  }

  // a later batch of the same scan keeps the image the user moved to; the first one preselects selectedImage
  function loadRows(rows) {
    var newImages = ImagePickerModel.loadRows(rows)
    var current = root.imagesLoaded && root.imageArray[root.selectedIndex] ? root.imageArray[root.selectedIndex].filePath : root.selectedImage
    root.selectedIndex = ImagePickerModel.indexForSelectedImage(newImages, current)
    root.imageArray = newImages
    root.rebuildFilterCache()
    root.imagesLoaded = true
    root.opened = true
    root.revealWhenSettled(root.requestSerial)
  }

  function startImageScan(serial) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      return
    }
    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.command = root.mode === 1 ? [root.pluginDir + "/list.nu", "themes", Paths.themes, Paths.wallpaperList] : [root.pluginDir + "/list.nu", Paths.wallpaperList]
    loadImagesProc.running = true
  }

  function scan() {
    filterField.clear()
    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    layoutSettled = false
    requestSerial += 1
    startImageScan(requestSerial)
  }

  function switchMode() {
    root.mode = root.mode === 1 ? 0 : 1
    root.selectedImage = ""
    root.scan()
  }

  // payload: {mode: 0 wallpapers | 1 themes, selectedImage: path to preselect}
  function open(args) {
    args = args || {}
    mode = args.mode === 1 ? 1 : 0
    selectedImage = String(args.selectedImage || selectedImage)
    opened = false
    scan()
  }

  function close() {
    cancel()
  }

  onFilterTextChanged: {
    rebuildFilterCache()
    if (!itemMatches(selectedIndex)) {
      const first = firstMatchingIndex()
      if (first >= 0) selectedIndex = first
    }
  }
  onSelectedIndexChanged: {
    root.preview = null
    quantizeDelay.restart()
  }
  onImageArrayChanged: quantizeDelay.restart()
  onOpenedChanged: {
    if (opened) {
      Qt.callLater(function() {
        filterField.forceActiveFocus()
      })
      return
    }
    layoutSettled = false
    quantizeDelay.stop()
    quantizer.source = ""
  }

  ColorQuantizer {
    id: quantizer
    depth: root.quantizeDepth
    rescaleSize: root.quantizeSize
    onColorsChanged: {
      try {
        const raw = ImagePickerModel.rawFromSwatches(quantizer.colors)
        root.preview = raw.special ? Colors.conditionPalette(raw) : null
      } catch (e) {
        root.preview = null
      }
    }
  }

  Timer {
    id: quantizeDelay
    interval: Style.motion.slow
    onTriggered: {
      var image = root.imageArray[root.selectedIndex]
      quantizer.source = root.opened && root.showPalette && image ? Util.fileUrl(image.thumbnailPath || image.filePath) : ""
    }
  }

  Timer {
    id: streamFlush
    interval: 120
    onTriggered: {
      if (loadImagesProc.activeSerial === root.requestSerial && loadImagesProc.streamBuffer.length > 0) {
        loadImagesProc.loadedBuffer = loadImagesProc.streamBuffer
        root.loadRows(loadImagesProc.streamBuffer)
      }
    }
  }

  Process {
    id: loadImagesProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string streamBuffer: ""
    // what streamFlush already showed, so the exit does not load the same rows twice
    property string loadedBuffer: ""

    onExited: {
      streamFlush.stop()
      if (activeSerial === root.requestSerial && streamBuffer !== loadedBuffer) root.loadRows(streamBuffer)
      streamBuffer = ""
      loadedBuffer = ""
      var serial = queuedSerial
      activeSerial = 0
      queuedSerial = 0
      if (serial > 0 && serial === root.requestSerial) root.startImageScan(serial)
    }

    stdout: SplitParser {
      onRead: function(line) {
        if (loadImagesProc.activeSerial !== root.requestSerial) return
        if (!line) return
        loadImagesProc.streamBuffer += line + "\n"
        streamFlush.restart()
      }
    }
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
      opacity: boot.progress
      width: Math.min(parent.width - Style.space(80), root.expandedWidth + root.sliceCount * (root.sliceWidth + root.sliceSpacing) + Style.space(40))
      height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight
      anchors.centerIn: parent

      MouseArea {
        anchors.fill: parent
        onClicked: {}
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
        visible: root.ready

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

            onNearbyChanged: if (nearby) sourceActivated = true
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
              }

              Image {
                anchors.fill: parent
                source: (item.selected && item.sourceActivated && item.filePath) ? Util.fileUrl(item.filePath) : ""
                sourceSize.width: Math.ceil(root.expandedWidth * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
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

              layer.effect: Glow {}
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: item.selected ? root.applySelected() : root.select(item.index)
            }

            SlowMove on x { enabled: root.layoutSettled }
            SlowMove on y { enabled: root.layoutSettled }
            SlowMove on width { enabled: root.layoutSettled }
            SlowMove on height { enabled: root.layoutSettled }
          }
        }
      }

      Row {
        id: paletteStrip
        visible: root.showPalette && root.ready
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

            Label {
              anchors.horizontalCenter: parent.horizontalCenter
              text: parent.modelData[0]
              dim: true
              caption: true
            }
          }
        }

        Label {
          text: root.preview ? ":: " + root.preview.verdict : ":: --"
          color: !root.preview ? root.foreground : root.preview.verdict === "OK" ? Colors.okText : Colors.warnText
          font.bold: true
        }
      }

      Label {
        anchors.centerIn: carousel
        visible: !root.ready
        text: root.imagesLoaded && root.imageArray.length === 0 ? "> NO IMAGES" : "> LOADING"
        dim: true
      }

      TextField {
        id: filterField
        anchors.top: root.showPalette ? paletteStrip.bottom : carousel.bottom
        anchors.horizontalCenter: carousel.horizontalCenter
        width: Math.min(root.expandedWidth, Style.space(360))
        // shown only once something is typed; it keeps the key focus while collapsed, which visible: false would drop
        height: text !== "" ? implicitHeight : 0
        opacity: text !== "" ? 1 : 0
        anchors.topMargin: text !== "" ? Style.spacing.md : 0
        foreground: root.foreground
        accent: root.selectedBorder
        placeholderText: "filter by name"
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (text) clear()
            else root.cancel()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.applySelected()
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier))
            root.selectAdjacent(-1)
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.selectAdjacent(1)
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) root.switchMode()
          else return
          event.accepted = true
        }
      }

      Label {
        visible: root.ready
        anchors.top: filterField.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.currentLabel()
        color: root.foreground
        style: Text.Outline
        styleColor: Util.alpha(root.dimColor, 0.7)
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
