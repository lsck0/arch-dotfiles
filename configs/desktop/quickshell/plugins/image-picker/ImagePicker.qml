import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "ImagePickerModel.js" as ImagePickerModel

Item {
  id: root

  readonly property string pluginDir: Paths.plugin("image-picker")

  // wallpaper-list.py filters for the largest connected screen in physical pixels
  readonly property string screenSize: {
    var best = null
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screen = Quickshell.screens[i]
      var dpr = screen.devicePixelRatio || 1
      var size = [Math.round(screen.width * dpr), Math.round(screen.height * dpr)]
      if (!best || size[0] * size[1] > best[0] * best[1]) best = size
    }
    return best ? best[0] + "x" + best[1] : ""
  }
  // themes mode reads each theme json's "wallpaper" field
  property string themeDirs: Paths.themes
  // 0 = wallpapers (wallust palette), 1 = premade themes
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
  property var doneFilesToRelease: []
  property var imageArray: []

  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color scrim: Color.imagePicker.scrim
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder
  property int expandedWidth: Style.space(768)
  property int expandedHeight: Style.space(475)
  property int sliceWidth: Style.space(108)
  property int sliceHeight: Style.space(432)
  // slices overlap by their skew
  property int sliceSpacing: -Style.space(30)
  property int skewOffset: Style.space(28)
  // slices either side of the preview the carousel lays out
  readonly property int sliceCount: 13
  readonly property int nearbyRange: 16
  // palette strip under the preview, wallpaper mode only
  readonly property bool showPalette: mode === 0
  readonly property int paletteHeight: showPalette ? Style.space(40) : 0
  property int bottomChromeHeight: paletteHeight
    + (showLabels ? (filterable ? Style.space(104) : Style.space(74)) : (filterable ? Style.space(60) : Style.space(30)))

  // palette preview (signature D): the selected wallpaper quantized, conditioned like Color.qml would
  property var preview: null
  readonly property int quantizeDepth: 3
  readonly property int quantizeSize: 64

  ColorQuantizer {
    id: quantizer
    depth: root.quantizeDepth
    rescaleSize: root.quantizeSize
    onColorsChanged: {
      try {
        var raw = ImagePickerModel.rawFromSwatches(quantizer.colors)
        root.preview = raw.special ? Color.conditionPalette(raw) : null
      } catch (e) {
        root.preview = null
      }
    }
  }

  // only the selected item is quantized, once the selection rests
  Timer {
    id: quantizeDelay
    interval: Style.motion.slow
    onTriggered: {
      var image = root.imageArray[root.selectedIndex]
      quantizer.source = root.opened && root.showPalette && image
        ? Util.fileUrl(image.thumbnailPath || image.filePath) : ""
    }
  }
  onSelectedIndexChanged: { root.preview = null; quantizeDelay.restart() }
  onImageArrayChanged: quantizeDelay.restart()

  onOpenedChanged: {
    if (opened) return
    layoutSettled = false
    quantizeDelay.stop()
    quantizer.source = ""
  }

  function rebuildFilterCache() {
    var matches = []
    var positions = []
    var count = 0
    var needle = String(filterText || "").toLowerCase()
    for (var i = 0; i < imageArray.length; i++) {
      var image = imageArray[i]
      var path = String(image.filePath || "")
      var matched = !needle
        || nameForPath(path).toLowerCase().indexOf(needle) !== -1
        || labelForPath(path).toLowerCase().indexOf(needle) !== -1
        || labelForImage(image).toLowerCase().indexOf(needle) !== -1
      matches.push(matched)
      positions.push(matched ? count++ : -1)
    }
    filterMatches = matches
    filterPositions = positions
    filteredCount = count
  }

  function scriptPath(name) {
    return root.pluginDir + "/" + name
  }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled)
      carousel.forceActiveFocus()
  }

  function revealWhenSettled(serial) {
    Qt.callLater(function() {
      if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) {
        root.layoutSettled = true
        root.focusPicker()
      }
    })
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function nameForPath(path) {
    return ImagePickerModel.nameForPath(path)
  }

  function labelForPath(path) {
    return ImagePickerModel.labelForPath(path)
  }

  function labelForImage(image) {
    return ImagePickerModel.labelForImage(image)
  }

  function currentLabel() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return filterText ? "No matches" : ""

    return labelForImage(imageArray[selectedIndex])
  }

  function itemMatches(index) {
    return index >= 0 && index < filterMatches.length ? filterMatches[index] : false
  }

  function firstMatchingIndex() {
    for (var i = 0; i < filterMatches.length; i++) {
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

  function select(index, immediate) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return

    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
    }
  }

  function updateFilter(nextFilterText) {
    filterText = nextFilterText
    rebuildFilterCache()

    if (!itemMatches(selectedIndex)) {
      var first = firstMatchingIndex()
      if (first >= 0) selectedIndex = first
    }
  }

  function releaseNextDoneFile() {
    if (releaseProc.running || doneFilesToRelease.length === 0) return

    var path = doneFilesToRelease.shift()
    releaseProc.command = ["bash", "-c", ": > " + Util.shellQuote(path)]
    releaseProc.running = true
  }

  function finishDoneFile(path) {
    if (!path) return
    doneFilesToRelease.push(path)
    releaseNextDoneFile()
  }

  function applySelected() {
    var path = currentPath()
    if (!path || !selectionFile) {
      cancel()
      return
    }

    var activeSelectionFile = selectionFile
    var activeDoneFile = doneFile
    applySerial = requestSerial
    requestActive = false
    selectionFile = ""
    doneFile = ""

    applyProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(path) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    applyProc.running = true
  }

  function cancel() {
    if (requestActive)
      finishDoneFile(doneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    root.opened = false
  }

  function loadRows(rows, reveal) {
    var newImages = ImagePickerModel.loadRows(rows)

    root.loadedImageRows = rows
    root.selectedIndex = root.indexForSelectedImage(newImages)
    root.imageArray = newImages
    root.rebuildFilterCache()
    root.imagesLoaded = true

    if (reveal !== false) {
      root.opened = true
      root.revealWhenSettled(root.requestSerial)
    }
  }

  function openSelector(nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      root.select(root.selectedImageIndex(), true)
      root.rebuildFilterCache()
      imagesLoaded = true
      opened = true
      root.revealWhenSettled(requestSerial)
      return
    }

    if (imageRows) {
      var rowsToLoad = imageRows
      var rowsSerial = requestSerial
      imageArray = []
      selectedIndex = 0
      imagesLoaded = true
      opened = true
      Qt.callLater(function() {
        if (rowsSerial === root.requestSerial)
          root.loadRows(rowsToLoad, true)
      })
      return
    }

    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    startImageScan(requestSerial)
  }

  function startImageScan(serial) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      return
    }

    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.command = root.mode === 1
      ? [root.scriptPath("theme-list.sh"), root.themeDirs, Paths.wallpaperList]
      : [root.scriptPath("list.sh"), Paths.wallpaperList, root.screenSize]
    loadImagesProc.running = true
  }

  function switchMode() {
    var next = root.mode === 1 ? 0 : 1
    root.mode = next
    root.filterText = ""
    root.selectedImage = ""
    root.imageArray = []
    root.selectedIndex = 0
    root.imagesLoaded = false
    root.layoutSettled = false
    root.requestSerial += 1
    root.startImageScan(root.requestSerial)
  }

  // batches streamed rows instead of one rebuild per line
  Timer {
    id: streamFlush
    interval: 120
    onTriggered: {
      if (loadImagesProc.activeSerial === root.requestSerial && loadImagesProc.streamBuffer.length > 0)
        root.loadRows(loadImagesProc.streamBuffer, true)
    }
  }

  function indexForSelectedImage(images) {
    return ImagePickerModel.indexForSelectedImage(images, selectedImage)
  }

  function selectedImageIndex() {
    return indexForSelectedImage(imageArray)
  }

  Process {
    id: loadImagesProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string streamBuffer: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        if (loadImagesProc.activeSerial !== root.requestSerial) return
        if (!line) return
        loadImagesProc.streamBuffer += line + "\n"
        streamFlush.restart()
      }
    }
    onExited: {
      if (activeSerial === root.requestSerial && streamBuffer.length > 0)
        root.loadRows(streamBuffer, true)
      streamBuffer = ""
      var serial = queuedSerial
      activeSerial = 0
      queuedSerial = 0
      if (serial > 0 && serial === root.requestSerial)
        root.startImageScan(serial)
    }
  }

  // called by shell.summon with the parsed payload
  function open(args) {
    var tDirs = String(args.themeDirs || themeDirs)
    var rows = String(args.imageRows || "")
    var sel = String(args.selectedImage || selectedImage)
    var selFile = String(args.selectionFile || "")
    var doneF = String(args.doneFile || "")
    var labels = args.showLabels === true || args.showLabels === "true"
    var filter = args.filterable === true || args.filterable === "true"
    themeDirs = tDirs
    mode = args.mode === 1 ? 1 : 0
    openSelector(rows, sel, selFile, doneF, labels, filter)
  }

  function close() {
    cancel()
  }

  Process {
    id: applyProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Process {
    id: releaseProc
    onExited: root.releaseNextDoneFile()
  }

  BootIn {
    id: boot
    active: root.opened
    title: root.modeNames[root.mode] || ""
    span: Math.min(root.expandedWidth, root.expandedHeight) / 2
  }

  PanelWindow {
    // mapped until the close has played out
    visible: root.opened || boot.progress > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

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
      // the layout resets on close, so the exit fades what was last shown
      visible: root.imagesLoaded && root.imageArray.length > 0 && (root.opened ? root.layoutSettled : boot.progress > 0)
      opacity: boot.progress
      width: Math.min(parent.width - Style.space(80), root.expandedWidth + root.sliceCount * (root.sliceWidth + root.sliceSpacing) + Style.space(40))
      height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: carousel
        anchors.top: parent.top
        anchors.topMargin: Style.space(30)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomChromeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + root.sliceCount * (root.sliceWidth + root.sliceSpacing)
        clip: false
        focus: true

        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) {
              root.updateFilter("")
            } else {
              root.cancel()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applySelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterable) root.updateFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
            root.selectAdjacent(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.selectAdjacent(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.switchMode()
            event.accepted = true
          } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.updateFilter(root.filterText + event.text)
            event.accepted = true
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
            onNearbyChanged: if (nearby) sourceActivated = true

            visible: nearby
            x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            width: selected ? root.expandedWidth : root.sliceWidth
            height: selected ? root.expandedHeight : root.sliceHeight
            y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
            z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

            // slides and grows on selection; off until the first layout so opening does not fly in
            Behavior on x { enabled: root.layoutSettled; NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
            Behavior on y { enabled: root.layoutSettled; NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
            Behavior on width { enabled: root.layoutSettled; NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
            Behavior on height { enabled: root.layoutSettled; NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }

            readonly property real skAbs: Math.abs(root.skewOffset)
            readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
            readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
            readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
            readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

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
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              // thumbnail below, full-res original fades in on top
              Image {
                anchors.fill: parent
                source: !item.sourceActivated ? "" : Util.fileUrl(item.thumbnailPath || item.filePath)
                // decode at draw width: every delegate stays alive
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
                // only one full-res image is shown, do not cache them
                cache: false
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
              }

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(root.dimColor, item.selected ? 0 : 0.42)
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              layer.enabled: item.selected && Style.fx.glow > 0
              layer.effect: Glow {}
              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                strokeWidth: item.selected ? Style.focusBorderWidth : Style.normalBorderWidth
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: item.selected ? root.applySelected() : root.select(index)
            }
          }
        }
      }

      // bg fg acc acc2 urg of the selected wallpaper, then the contrast verdict
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
              color: root.foreground
              opacity: Style.emphasis.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.preview ? ":: " + root.preview.verdict : ":: --"
          color: !root.preview ? root.foreground : root.preview.verdict === "OK" ? Color.ok : Color.warn
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      BorderSurface {
        id: searchChip
        readonly property bool focused: searchInput.activeFocus
        readonly property bool hot: searchHover.hovered
        visible: root.filterable && root.filterText.length > 0

        // every way out of the search field must hand focus back
        onVisibleChanged: if (!visible && root.opened) carousel.forceActiveFocus()

        anchors.top: root.showPalette ? paletteStrip.bottom : carousel.bottom
        anchors.topMargin: Style.spacing.md
        anchors.horizontalCenter: carousel.horizontalCenter
        width: Math.min(root.expandedWidth, Style.space(360))
        height: Style.space(38)
        radius: Style.shape.data
        color: Style.controlFill(focused, hot, root.foreground, root.selectedBorder)
        borderSpec: Border.controlSpec(focused ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, root.selectedBorder)

        HoverHandler { id: searchHover }

        OpticalGlyph {
          id: searchIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          text: "\u{ea6d}" // cod-search, cmap-verified
          fontSize: Style.font.body
          color: Util.alpha(root.foreground, Style.emphasis.dim)
        }

        TextInput {
          id: searchInput
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: searchIcon.right
          anchors.leftMargin: Style.spacing.xs
          anchors.right: clearButton.left
          anchors.rightMargin: Style.spacing.xs
          verticalAlignment: TextInput.AlignVCenter
          text: root.filterText
          color: root.foreground
          selectionColor: root.selectedBorder
          selectedTextColor: root.dimColor
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          focus: searchChip.visible
          activeFocusOnPress: true
          selectByMouse: true
          clip: true
          onTextChanged: if (text !== root.filterText) root.updateFilter(text)
          onAccepted: carousel.forceActiveFocus()
          Keys.onEscapePressed: function (event) {
            if (text.length > 0) {
              text = ""
              carousel.forceActiveFocus()
            } else {
              root.cancel()
            }
            event.accepted = true
          }
          Keys.onUpPressed: function (event) { root.switchMode(); event.accepted = true }
          Keys.onDownPressed: function (event) { root.switchMode(); event.accepted = true }
        }

        Item {
          id: clearButton
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xs
          width: Style.space(22)
          height: Style.space(22)

          OpticalGlyph {
            anchors.centerIn: parent
            text: "\u{f0156}" // md-close, cmap-verified
            fontSize: Style.font.caption
            color: Util.alpha(root.foreground, clearHover.hovered ? Style.emphasis.strong : Style.emphasis.dim)
          }

          HoverHandler { id: clearHover }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.updateFilter("")
              carousel.forceActiveFocus()
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.showLabels
        anchors.top: root.filterable ? searchChip.bottom : root.showPalette ? paletteStrip.bottom : carousel.bottom
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
          decor: true
          blinking: root.opened
        }
      }

      HudFrame { inset: boot.bracketInset }
    }

    Scanlines { flicker: true }
  }
}
