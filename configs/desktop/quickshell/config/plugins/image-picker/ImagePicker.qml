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
  readonly property string credits: Paths.dotfiles + "/wallpapers/CREDITS.md"
  // dot theme's record of the last picks (configs/core/wallust/scripts/wallpaper.nu)
  readonly property string recentFile: Paths.envDir("XDG_STATE_HOME", Paths.home + "/.local/state") + "/dotfiles/theme-recent.json"
  property int mode: 0
  property var modeNames: ["Wallpapers", "Themes"]
  // per mode, the pick in effect: the wallpaper's path, the theme's name ("" under a derived palette)
  property var current: ["", ""]
  readonly property int pageStep: 10
  // a held arrow moves one more image per heldPerStep repeats, up to heldStepMax
  readonly property int heldPerStep: 8
  readonly property int heldStepMax: 4
  property int heldRepeats: 0
  property var recentPicks: []
  readonly property int recentShown: 3
  // the tiles under the slices: the last wallpapers left of the preview, the last themes right of it
  readonly property var recentTiles: ImagePickerModel.recentTiles(recentPicks, current, recentShown)
  // the tile Ctrl+Left/Right focused and the one under the pointer, -1 for none
  property int recentIndex: -1
  property int recentHovered: -1
  readonly property int recentTileWidth: Style.space(100)
  readonly property int recentTileHeight: Style.space(56)
  // the slices' slant, on a tile's height
  readonly property real recentSkew: skewOffset * recentTileHeight / sliceHeight

  // The lottery (Ctrl+R wallpaper, Ctrl+T theme): the result is drawn first, then the carousel spins to it over
  // lotterySpinMs, slowing all the way, at least lotteryStepsMin images far and whole laps further when the draw is
  // nearer, at most lotteryStepsMax: a draw further off starts that close to it, so a long list costs no more frames
  // or thumbnails than a short one; landed, the stroke blinks and the chime rings lotteryDings times, and
  // lotteryBeatMs later the pick is applied as Enter does.
  readonly property int lotterySpinMs: 2000
  readonly property int lotteryStepsMin: 24
  readonly property int lotteryStepsMax: 48
  readonly property int lotteryDings: 3
  readonly property int lotteryDingMs: 130
  readonly property int lotteryBeatMs: 250
  // a lottery that waits for the other source's scan
  property bool lotteryPending: false
  property bool lotteryRunning: false
  // the show without its effects: nothing applied (ipc `image-picker lottery true`)
  property bool lotteryDry: false
  property int lotteryTarget: -1
  property int lotteryStart: 0
  property real lotteryTravel: 0
  property real lotteryStroke: 1
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool layoutSettled: false
  readonly property bool ready: imagesLoaded && imageArray.length > 0 && (!opened || layoutSettled)
  property int requestSerial: 0
  readonly property string filterText: filterField.text
  property var filterPositions: []
  // the matching images' indices in carousel order
  property var filterOrder: []
  readonly property int filteredCount: filterOrder.length
  property var imageArray: []
  readonly property color unselectedBorder: Util.alpha(Colors.foreground, 0.28)
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
  property int bottomChromeHeight: paletteHeight + Style.space(104) + keyHints.height + Style.spacing.sm
  property var preview: null
  readonly property int quantizeDepth: 3
  readonly property int quantizeSize: 64

  function rebuildFilterCache() {
    var words = filterText.toLowerCase().split(/\s+/).filter(Boolean)
    var order = []
    filterPositions = imageArray.map(function(image, index) { return ImagePickerModel.matches(image, words) ? order.push(index) - 1 : -1 })
    filterOrder = order
  }

  readonly property var selected: itemMatches(selectedIndex) ? imageArray[selectedIndex] : null
  readonly property int selectedPosition: Math.max(0, filteredPosition(selectedIndex))

  function currentLabel() {
    var tile = recentTiles[recentHovered >= 0 ? recentHovered : recentIndex]
    if (tile) return tile.label
    if (!selected) return filterText ? "No matches" : ""
    return ImagePickerModel.labelForImage(selected)
  }

  function itemMatches(index) {
    return filteredPosition(index) >= 0
  }

  function filteredPosition(index) {
    return index >= 0 && index < filterPositions.length ? filterPositions[index] : -1
  }

  function select(index) {
    if (index >= 0 && index < imageArray.length && itemMatches(index)) selectedIndex = index
  }

  // by position among the matching images: a step wraps around the ends, a jump stops at them
  function selectAt(position, wrap) {
    var count = filteredCount
    if (count > 0) select(filterOrder[wrap ? ((position % count) + count) % count : Math.max(0, Math.min(count - 1, position))])
  }

  // dot theme takes a theme by its name, a wallpaper by its path (shown under its own derived palette), or `random`
  function apply(pick) {
    if (!pick) return
    Quickshell.execDetached([root.dot, "theme", pick])
    root.cancel()
  }

  function applySelected() {
    if (selected) apply(ImagePickerModel.pickFor(selected))
  }

  function lottery(source) {
    if (lotteryRunning || lotteryPending) return
    // a scan in flight draws when it lands: the list it would draw from now is the last mode's
    if (mode === source && imagesLoaded) return lotteryDraw()
    lotteryPending = true
    if (mode !== source) switchMode()
  }

  function lotteryDraw() {
    var count = filteredCount
    if (count === 0) return lotteryCancel()
    lotteryStart = selectedPosition
    // never the image the carousel is on, so the wheel always turns
    var steps = count === 1 ? 0 : 1 + Math.floor(Math.random() * (count - 1))
    lotteryTarget = filterOrder[(lotteryStart + steps) % count]
    lotteryRunning = true
    if (count === 1 || Power.saver) return lotteryLand()
    while (steps < lotteryStepsMin) steps += count
    if (steps > lotteryStepsMax) {
      lotteryStart = (lotteryStart + steps - lotteryStepsMax) % count
      steps = lotteryStepsMax
      selectAt(lotteryStart, true)
    }
    lotterySpin.to = steps
    lotterySpin.restart()
  }

  function lotteryLand() {
    select(lotteryTarget)
    lotteryDing.restart()
  }

  function lotteryFinish() {
    var dry = lotteryDry
    lotteryCancel()
    if (!dry) applySelected()
  }

  // the carousel stays where it stopped
  function lotteryCancel() {
    lotterySpin.stop()
    lotteryDing.stop()
    lotteryStroke = 1
    lotteryPending = false
    lotteryRunning = false
    lotteryDry = false
    lotteryTarget = -1
  }

  function themePalette(raw) {
    try {
      return raw ? Colors.conditionPalette(raw) : null
    } catch (e) {
      return null
    }
  }

  // a new serial drops the scan still streaming, so its late rows cannot reopen the picker
  function cancel() {
    root.lotteryCancel()
    root.requestSerial += 1
    root.opened = false
  }

  // a later batch of the same scan keeps the image the user moved to; the first one preselects what is in effect
  function loadRows(rows) {
    var newImages = ImagePickerModel.loadRows(rows)
    var pick = root.imagesLoaded && root.imageArray[root.selectedIndex] ? ImagePickerModel.pickFor(root.imageArray[root.selectedIndex]) : root.current[root.mode]
    root.selectedIndex = ImagePickerModel.indexOfPick(newImages, pick)
    root.imageArray = newImages
    root.rebuildFilterCache()
    root.imagesLoaded = true
    root.opened = true
    var serial = root.requestSerial
    Qt.callLater(function() {
      if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) root.layoutSettled = true
    })
  }

  function startImageScan(serial) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      return
    }
    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.command = [root.pluginDir + "/list.nu"].concat(root.mode === 1 ? ["themes", Paths.themes] : [], [Paths.wallpaperList, root.credits])
    loadImagesProc.running = true
  }

  function scan() {
    imageArray = []
    rebuildFilterCache()
    selectedIndex = 0
    imagesLoaded = false
    layoutSettled = false
    requestSerial += 1
    startImageScan(requestSerial)
  }

  function switchMode() {
    root.mode = root.mode === 1 ? 0 : 1
    root.scan()
  }

  // payload: {mode: 0 wallpapers | 1 themes, wallpaper: the path on screen, theme: the theme in effect or ""}
  function open(args) {
    args = args || {}
    lotteryCancel()
    mode = args.mode === 1 ? 1 : 0
    current = [String(args.wallpaper || ""), String(args.theme || "")]
    opened = false
    recentIndex = -1
    recentHovered = -1
    filterField.clear()
    recentProc.running = true
    scan()
  }

  onFilterTextChanged: {
    recentIndex = -1
    rebuildFilterCache()
    if (!itemMatches(selectedIndex) && filterOrder.length > 0) selectedIndex = filterOrder[0]
  }
  onLotteryTravelChanged: if (lotterySpin.running) selectAt(lotteryStart + Math.floor(lotteryTravel), true)
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

  IpcHandler {
    target: "image-picker"

    function close(): string { root.cancel(); return "ok" }
    function lottery(dry: bool): string {
      if (!root.opened) return "closed"
      if (root.lotteryRunning || root.lotteryPending) return "busy"
      root.lotteryDry = dry
      root.lottery(root.mode)
      return "ok"
    }
  }

  NumberAnimation {
    id: lotterySpin
    target: root
    property: "lotteryTravel"
    from: 0
    duration: root.lotterySpinMs
    // the last images pass one by one, slow enough to follow
    easing.type: Easing.OutCubic
    onFinished: root.lotteryLand()
  }

  SequentialAnimation {
    id: lotteryDing

    SequentialAnimation {
      loops: root.lotteryDings

      NumberAnimation { target: root; property: "lotteryStroke"; to: Style.emphasis.disabled; duration: root.lotteryDingMs / 2; easing.type: Style.motion.ambientEasing }
      NumberAnimation { target: root; property: "lotteryStroke"; to: 1; duration: root.lotteryDingMs / 2; easing.type: Style.motion.ambientEasing }
    }
    PauseAnimation { duration: root.lotteryBeatMs }
    ScriptAction { script: root.lotteryFinish() }
  }

  Process {
    id: recentProc
    command: [root.pluginDir + "/list.nu", "recent", Paths.themes, Paths.wallpaperList, root.recentFile]
    stdout: StdioCollector { id: recentOut; waitForEnd: true }
    onExited: root.recentPicks = ImagePickerModel.loadRecent(recentOut.text)
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
      if (activeSerial === root.requestSerial && root.lotteryPending) {
        root.lotteryPending = false
        root.lotteryDraw()
      }
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

    Scrim {
      shown: root.opened || boot.progress > 0
      progress: boot.progress
      interactive: root.opened
      onClicked: root.cancel()
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
            readonly property int relativeIndex: root.filteredPosition(index) - root.selectedPosition
            readonly property bool selected: matched && index === root.selectedIndex
            readonly property bool nearby: matched && Math.abs(relativeIndex) <= root.nearbyRange
            property bool sourceActivated: nearby
            readonly property var outline: [Qt.point(root.skewOffset, 0), Qt.point(width, 0), Qt.point(width - root.skewOffset, height),
              Qt.point(0, height), Qt.point(root.skewOffset, 0)]

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
                  PathPolyline { path: item.outline }
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
                // a lottery passes the images at slice size: only the one it lands on is decoded again for the preview
                sourceSize.width: Math.ceil((item.selected && (!root.lotteryRunning || item.index === root.lotteryTarget) ? root.expandedWidth : root.sliceWidth) * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Image {
                anchors.fill: parent
                // a lottery loads no preview but the one it lands on, from its start
                source: item.filePath && (root.lotteryRunning ? item.index === root.lotteryTarget : item.selected && item.sourceActivated) ? Util.fileUrl(item.filePath) : ""
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
                color: Util.alpha(Colors.background, item.selected ? 0 : 0.42)
                Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
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
              opacity: item.selected ? root.lotteryStroke : 1

              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? Colors.accent : root.unselectedBorder
                strokeWidth: item.selected ? Style.focusBorderWidth : Style.normalBorderWidth
                PathPolyline { path: item.outline }
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
          model: [["BG", "background"], ["FG", "foreground"], ["ACC", "accent"], ["ACC2", "accent2"], ["URG", "urgent"]]

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
          color: !root.preview ? Colors.foreground : root.preview.verdict === "OK" ? Colors.okText : Colors.warnText
          font.bold: true
        }
      }

      Component {
        id: recentTile

        Column {
          id: tile
          required property var modelData
          readonly property var swatches: root.themePalette(modelData.palette)
          readonly property bool marked: modelData.slot === root.recentIndex || modelData.slot === root.recentHovered

          spacing: Style.spacing.xxs

          Item {
            width: root.recentTileWidth
            height: root.recentTileHeight

            // sheared into the slices' slant; the image inside is sheared back, so the slant only crops it
            Item {
              width: parent.width - root.recentSkew
              height: parent.height
              clip: true
              transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, -root.recentSkew / root.recentTileHeight, 0, root.recentSkew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
              }

              Image {
                width: parent.width + root.recentSkew
                height: parent.height
                source: Util.fileUrl(tile.modelData.thumbnailPath)
                sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                transform: Matrix4x4 {
                  matrix: Qt.matrix4x4(1, root.recentSkew / root.recentTileHeight, 0, -root.recentSkew, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
              }

              Rectangle {
                anchors.fill: parent
                color: "transparent"
                antialiasing: true
                border.width: tile.marked ? Style.focusBorderWidth : Style.normalBorderWidth
                border.color: tile.marked ? Colors.accent : root.unselectedBorder
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: root.recentHovered = containsMouse ? tile.modelData.slot : root.recentHovered === tile.modelData.slot ? -1 : root.recentHovered
              onClicked: root.apply(tile.modelData.pick)
            }
          }

          Row {
            visible: tile.swatches !== null

            Repeater {
              model: ["background", "foreground", "accent", "accent2", "urgent"]

              Rectangle {
                required property string modelData

                width: (root.recentTileWidth - root.recentSkew) / 5
                height: Style.spacing.xs
                color: tile.swatches ? tile.swatches[modelData] : "transparent"
              }
            }
          }
        }
      }

      Item {
        id: recentGroups
        readonly property real groupWidth: root.recentShown * (root.recentTileWidth + Style.spacing.sm)
        readonly property real gap: root.expandedWidth / 2 + Style.spacing.lg

        // both groups or neither: the room left of the preview is the room right of it
        visible: root.ready && root.recentTiles.length > 0 && (parent.width - root.expandedWidth) / 2 >= groupWidth + Style.spacing.lg
        anchors.top: carousel.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.horizontalCenter: carousel.horizontalCenter

        Repeater {
          model: [["wallpaper", "last wallpapers"], ["theme", "last themes"]]

          Column {
            id: recentGroup
            required property var modelData
            required property int index
            readonly property var tiles: root.recentTiles.filter(function(tile) { return tile.kind === recentGroup.modelData[0] })

            visible: tiles.length > 0
            x: index === 0 ? -recentGroups.gap - width : recentGroups.gap
            spacing: Style.spacing.xs

            Label {
              anchors.right: recentGroup.index === 0 ? parent.right : undefined
              text: recentGroup.modelData[1]
              dim: true
              caption: true
              font.capitalization: Font.AllUppercase
            }

            Row {
              anchors.right: recentGroup.index === 0 ? parent.right : undefined
              spacing: Style.spacing.sm

              Repeater {
                model: recentGroup.tiles
                delegate: recentTile
              }
            }
          }
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
        placeholderText: "filter"
        Keys.onPressed: function(event) {
          const key = event.key
          const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          const enter = key === Qt.Key_Return || key === Qt.Key_Enter
          const direction = key === Qt.Key_Right || key === Qt.Key_Tab ? 1 : key === Qt.Key_Left || key === Qt.Key_Backtab ? -1 : 0
          root.heldRepeats = direction !== 0 && event.isAutoRepeat ? root.heldRepeats + 1 : 0
          const tiles = recentGroups.visible ? root.recentTiles.length : 0
          const tileStep = ctrl && (key === Qt.Key_Left || key === Qt.Key_Right)
          event.accepted = true
          if (root.lotteryRunning || root.lotteryPending) {
            // a running lottery takes Esc alone: it stops where it is and nothing is applied
            if (key === Qt.Key_Escape) root.lotteryCancel()
            return
          }
          if (ctrl && key === Qt.Key_R) root.lottery(0)
          else if (ctrl && key === Qt.Key_T) root.lottery(1)
          // through the tiles and back to the carousel, which is -1
          else if (tileStep) root.recentIndex = (root.recentIndex + 1 + direction + tiles + 1) % (tiles + 1) - 1
          else if (root.recentIndex >= 0 && enter) root.apply(root.recentTiles[root.recentIndex].pick)
          else if (root.recentIndex >= 0 && key === Qt.Key_Escape) root.recentIndex = -1
          else if (key === Qt.Key_Escape) {
            if (text) clear()
            else root.cancel()
          } else if (enter) root.applySelected()
          else if (direction !== 0) root.selectAt(root.selectedPosition + direction * Math.min(root.heldStepMax, 1 + Math.floor(root.heldRepeats / root.heldPerStep)), true)
          else if (key === Qt.Key_PageUp || key === Qt.Key_PageDown)
            root.selectAt(root.selectedPosition + (key === Qt.Key_PageDown ? root.pageStep : -root.pageStep), false)
          else if (key === Qt.Key_Home) root.selectAt(0, false)
          else if (key === Qt.Key_End) root.selectAt(root.filteredCount - 1, false)
          else if (key === Qt.Key_Up || key === Qt.Key_Down) root.switchMode()
          else event.accepted = false
          if (event.accepted && !tileStep) root.recentIndex = -1
        }
      }

      Label {
        visible: root.ready
        anchors.top: filterField.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.currentLabel()
        color: Colors.foreground
        style: Text.Outline
        styleColor: Util.alpha(Colors.background, 0.7)
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Item {
        id: titleLine
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
          suffix: !root.selected ? "[0]" : "[" + (root.selectedPosition + 1) + "/" + root.filteredCount + "]"
            + (root.selected.artist ? " :: " + root.selected.artist : "")
          blinking: root.opened
        }
      }

      KeyHints {
        id: keyHints
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.sm
        anchors.left: titleLine.left
        hints: [["</>", "select"], ["PGUP/PGDN", "ten"], ["^/v", root.mode === 1 ? "wallpapers" : "themes"]]
          .concat(recentGroups.visible ? [["CTRL+</>", "recent"]] : [],
            [["TYPE", "filter"], ["CTRL+R", "lottery"], ["CTRL+T", "theme lottery"], ["ENTER", "apply"], ["ESC", root.lotteryRunning || root.lotteryPending ? "stop" : root.recentIndex >= 0 ? "back" : root.filterText ? "clear" : "close"]])
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
