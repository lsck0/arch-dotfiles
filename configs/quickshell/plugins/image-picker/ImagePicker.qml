import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "ImagePickerModel.js" as ImagePickerModel

// Adapted from omarchy-shell almost verbatim -- the skewed-carousel image
// grid (Shape-masked slices, MultiEffect masking, filter-by-name) is
// unchanged; only the OMARCHY_PATH/env-var plumbing differs:
//   - scriptPath()/list.sh: this repo's own plugin dir instead of an
//     OMARCHY_PATH checkout.
//   - imageDirs default: upstream falls back through
//     OMARCHY_IMAGE_SELECTOR_DIRS/_DIR/_STOCK_BACKGROUNDS_DIR env vars to
//     Omarchy's own theme system (~/.local/state/omarchy/current/theme/
//     backgrounds) -- none of which exist here. Defaults to this repo's
//     own wallpapers/ directory instead.
//   - list.sh's thumbnail cache has no pre-generation step here (Omarchy
//     warms it during theme install; this repo has no equivalent), so
//     until a thumbnail happens to get cached some other way, images load
//     full-size -- list.sh's own fallback already handles this gracefully,
//     and only the ~16 carousel-adjacent images are ever actually loaded.
//   - Util.editsFilter/editedFilter (no local equivalent) -> the same
//     explicit Key_Backspace + printable-character handling
//     Clipboard.qml/AppSearch.qml/Emojis.qml already use.
//   - selectionFile/doneFile handshake protocol kept as-is: a caller
//     summons with a payload naming both, writes are polled by the
//     caller, not consumed by anything in this repo yet -- this is
//     Omarchy's own general-purpose "picker for a directory of images"
//     component, unwired to any specific consumer (not a replacement for
//     scripts/switch-wallpaper.sh's existing fzf+chafa interactive picker,
//     which stays as-is).
Item {
  id: root

  readonly property string pluginDir: Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/image-picker"
  property var shell: null
  property var manifest: null

  property string imageDirs: Quickshell.env("HOME") + "/projects/arch-dotfiles/wallpapers"
  // Handwritten premade themes, scanned as their own mode via theme-list.sh,
  // which reads each themes/*.json's own "wallpaper" field rather than
  // listing image files directly -- the JSON is the source of truth, not a
  // themes/wallpapers/<name> filename convention. themeDirs therefore
  // points at the directory of theme JSONs (themes/), not at a directory of
  // images. Selecting a result applies that theme's hand-authored palette
  // (switch-wallpaper.sh matches by each theme JSON's "wallpaper" field).
  property string themeDirs: Quickshell.env("HOME") + "/projects/arch-dotfiles/themes"
  // 0 = wallpapers (auto-generate palette via wallust), 1 = premade themes.
  // Up/Down switches; each mode scans its own directory set.
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
  // Cache filter results and filtered positions. Computing the match and
  // scanning all preceding images inside every delegate made each keystroke
  // O(n²), which was very noticeable with a large wallpaper directory.
  property var filterMatches: []
  property var filterPositions: []
  property int filteredCount: 0
  property var doneFilesToRelease: []

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
  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color scrim: Color.imagePicker.scrim
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)

  onOpenedChanged: if (!opened) layoutSettled = false

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

  // Themes mode: label by the theme JSON's own name (carried through
  // list rows as displayName), not by its wallpaper's filename.
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

  function closeSelector(nextDoneFile) {
    requestSerial += 1

    if (requestActive)
      finishDoneFile(doneFile)

    if (nextDoneFile && nextDoneFile !== doneFile)
      finishDoneFile(nextDoneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    filterText = ""
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

  function openSelector(nextImageDirs, nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageDirs = nextImageDirs
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
    startImageScan(requestSerial, root.activeDirs())
  }

  property var imageArray: []

  function startImageScan(serial, dirs) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      loadImagesProc.queuedDirs = dirs
      return
    }

    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.queuedDirs = ""
    // Themes mode (1) lists theme JSONs' own "wallpaper" fields via
    // theme-list.sh; wallpapers mode (0) lists image files directly via
    // list.sh. Both share list.sh's tsv contract and thumbnail cache.
    var script = root.mode === 1 ? "theme-list.sh" : "list.sh"
    loadImagesProc.command = [root.scriptPath(script), dirs]
    loadImagesProc.running = true
  }

  // The directory set for the active mode: wallpapers (auto-generate palette)
  // or the premade themes' wallpapers.
  function activeDirs() {
    return root.mode === 1 ? root.themeDirs : root.imageDirs
  }

  // Up/Down switches mode (wallpapers <-> themes) and re-scans the other
  // directory set. Clears the filter and selection so the carousel starts
  // fresh on the newly active group rather than pointing at a stale index.
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
    root.startImageScan(root.requestSerial, root.activeDirs())
  }

  // Coalesces the per-line stream into a few visible updates rather than
  // 262 model rebuilds — one per row would be far more expensive than the
  // wait it replaces.
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
    property string queuedDirs: ""
    // Streams. list.sh prints and flushes one row per image, so the
    // carousel can fill in as results arrive instead of waiting for the
    // whole directory walk. Was StdioCollector{waitForEnd:true}, which
    // blocked on the complete listing before showing anything.
    property string streamBuffer: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        if (loadImagesProc.activeSerial !== root.requestSerial) return
        if (!line) return
        loadImagesProc.streamBuffer += line + "\n"
        // Reveal on the first batch so something is on screen immediately,
        // then keep appending. Re-parsing the accumulated buffer is cheap
        // next to decoding an image and keeps one parser as the single
        // source of truth for row format.
        streamFlush.restart()
      }
    }
    onExited: {
      if (activeSerial === root.requestSerial && streamBuffer.length > 0)
        root.loadRows(streamBuffer, true)
      streamBuffer = ""
      var serial = queuedSerial
      var dirs = queuedDirs
      activeSerial = 0
      queuedSerial = 0
      queuedDirs = ""
      if (serial > 0 && serial === root.requestSerial)
        root.startImageScan(serial, dirs)
    }
  }

  // Lifecycle hooks invoked by shell.summon/shell.hide. shell.summon(id,
  // payloadJson) hands the JSON to open() here; shell.hide(id) calls close().
  function open(payload) {
    var args = {}
    if (payload) {
      try { args = JSON.parse(payload) || {} } catch (e) { args = {} }
    }
    var dirs = String(args.imageDirs || imageDirs)
    var tDirs = String(args.themeDirs || themeDirs)
    var rows = String(args.imageRows || "")
    var sel = String(args.selectedImage || selectedImage)
    var selFile = String(args.selectionFile || "")
    var doneF = String(args.doneFile || "")
    var labels = args.showLabels === true || args.showLabels === "true"
    var filter = args.filterable === true || args.filterable === "true"
    imageDirs = dirs
    themeDirs = tDirs
    // Which group to land on. The wallpaper picker passes mode 0 (wallpapers)
    // by default; a caller can open straight into the themes group with 1.
    if (args.mode === 1) mode = 1; else mode = 0
    openSelector(dirs, rows, sel, selFile, doneF, labels, filter)
  }

  function close() {
    cancel()
  }

  function preloadRows(nextImageRows, nextSelectedImage, nextShowLabels, nextFilterable) {
    // Theme/background set hooks can warm selector rows after a picker was
    // dismissed. Ignore those preloads while a user-visible request is open;
    // otherwise the preload resets layoutSettled without revealing again,
    // leaving only the fullscreen scrim.
    if (opened || requestActive) return

    requestSerial += 1
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      selectedIndex = selectedImageIndex()
      rebuildFilterCache()
      imagesLoaded = true
    } else if (imageRows) {
      loadRows(imageRows, false)
    }
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

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    // Was `root.opened && root.imagesLoaded`. switchMode() (Up/Down between
    // Wallpapers and Themes) clears imagesLoaded for the stretch between the
    // scan starting and the first batch streaming back, with root.opened
    // staying true throughout -- so this dropped keyboard focus to None and
    // reacquired Exclusive moments later on every single mode switch, and
    // the scrim+MouseArea below did the same for the dimmed backdrop,
    // producing a flash through to the desktop. Keeping all three keyed on
    // root.opened alone means a mode switch only ever swaps the carousel
    // contents, never the backdrop or the keyboard grab.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.cancel()
    }

    Item {
      id: card
      visible: root.opened && root.imagesLoaded && root.layoutSettled && root.imageArray.length > 0
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
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
          width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
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
              // Up/Down toggles between the two groups: wallpapers (auto-
              // generate the theme) and premade themes (each with its own
              // wallpaper + hand-authored palette).
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
              readonly property string fileName: imageData ? imageData.fileName : ""
              readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""

              readonly property bool matched: root.itemMatches(index)
              readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
              readonly property bool selected: matched && index === root.selectedIndex
              readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
              property bool sourceActivated: nearby
              onNearbyChanged: if (nearby) sourceActivated = true

              visible: nearby
              x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
              width: selected ? root.expandedWidth : root.sliceWidth
              height: selected ? root.expandedHeight : root.sliceHeight
              y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
              z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

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

                // Two layers, not one. The thumbnail (cached, a few hundred
                // px, decodes near-instantly) is always the base — it is
                // what every slice shows, selected or not. The selected
                // item ALSO loads its full-size original on top, since it's
                // displayed at 768x475 and a thumbnail there was visibly
                // soft; that decode is asynchronous but a multi-MB source
                // still takes real time. It used to be the *only* image, so
                // selecting a wallpaper meant an empty box for however long
                // that decode took. Now the thumbnail is already on screen
                // for that whole window, and the full-res layer just fades
                // in on top once ready — never a blank frame.
                Image {
                  id: thumbImage
                  anchors.fill: parent
                  source: !item.sourceActivated ? "" : Util.fileUrl(item.thumbnailPath || item.filePath)
                  fillMode: Image.PreserveAspectCrop
                  // Was false, which decoded every image on the UI thread —
                  // so opening the picker froze the shell while it worked
                  // through them. The carousel already windows which images
                  // activate; decoding those off-thread is what keeps it
                  // responsive while they arrive.
                  asynchronous: true
                  cache: true
                  smooth: true
                }

                Image {
                  id: fullImage
                  anchors.fill: parent
                  source: (item.selected && item.sourceActivated && item.filePath) ? Util.fileUrl(item.filePath) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  smooth: true
                  opacity: status === Image.Ready ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 150 } }
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
                ShapePath {
                  fillColor: "transparent"
                  strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                  strokeWidth: item.selected ? 3 : 1
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

        // Search chip: hidden until you type. The carousel's own Keys.onPressed
        // already accepts printable characters and calls updateFilter (see
        // its handler above), so a search box isn't needed just to START
        // typing — only to see/edit/clear the filter once it exists. Filling
        // that role only after there's something to show removes the empty
        // "Search wallpapers…" box that always sat under the carousel: one
        // less always-on element, same discoverability (the mode label
        // below still says "type to search" while empty).
        BorderSurface {
          id: searchChip
          readonly property bool focused: searchInput.activeFocus
          readonly property bool hot: searchHover.hovered
          visible: root.filterable && root.filterText.length > 0
          anchors.top: carousel.bottom
          anchors.topMargin: Style.space(10)
          anchors.horizontalCenter: carousel.horizontalCenter
          width: Math.min(root.expandedWidth, Style.space(360))
          height: Style.space(38)
          radius: Style.cornerRadius
          color: Style.controlFill(focused, hot, root.foreground, root.selectedBorder)
          borderSpec: Border.controlSpec(focused ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, root.selectedBorder)

          HoverHandler { id: searchHover }

          OpticalGlyph {
            id: searchIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            text: "\u{ea6d}" // cod-search, cmap-verified
            fontSize: Style.font.body
            color: Util.alpha(root.foreground, 0.65)
          }

          TextInput {
            id: searchInput
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: clearButton.left
            anchors.rightMargin: Style.spacing.sm
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
            Keys.onEscapePressed: {
              if (text.length > 0) {
                text = ""
                // Clearing drops searchChip.visible -> false, which in turn
                // reactively clears this field's own `focus: searchChip.visible`
                // binding -- but nothing else holds `focus: true` inside the
                // same scope at that instant, so active focus was landing
                // nowhere and every subsequent key (arrows, Tab, Enter) went
                // unhandled until the picker was closed and reopened. The
                // clear (x) button already worked around this the same way.
                carousel.forceActiveFocus()
              } else {
                root.cancel()
              }
              event.accepted = true
            }
            // Up/Down switches group from the search field too (focus lands
            // here when filterable). Enter commits the filter to the carousel.
            Keys.onUpPressed: { root.switchMode(); event.accepted = true }
            Keys.onDownPressed: { root.switchMode(); event.accepted = true }
          }

          Item {
            id: clearButton
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.sm
            width: Style.space(22)
            height: Style.space(22)

            OpticalGlyph {
              anchors.centerIn: parent
              text: "\u{f0156}" // md-close, cmap-verified
              fontSize: Style.font.caption
              color: Util.alpha(root.foreground, clearHover.hovered ? 1.0 : 0.6)
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
          id: selectedLabel
          textFormat: Text.PlainText
          visible: root.showLabels
          anchors.top: root.filterable ? searchChip.bottom : carousel.bottom
          anchors.topMargin: Style.space(8)
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
    }
  }
}
