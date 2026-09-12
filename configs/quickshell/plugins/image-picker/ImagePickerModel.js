// Verbatim from omarchy-shell: pure functions, no Omarchy-specific coupling.
function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function titleCase(name) {
  return name.replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function labelForPath(path) {
  return titleCase(nameForPath(path))
}

// Themes mode rows carry a 3rd tsv column: the theme JSON's own basename
// (see theme-list.sh), so a theme picked by its wallpaper's filename never
// shows the wallpaper's name -- it shows the theme's own name. Falls back
// to labelForPath for wallpapers-mode rows, which have no 3rd column.
function labelForImage(image) {
  if (image && image.displayName) return titleCase(image.displayName)
  return labelForPath(image ? image.filePath : "")
}

function loadRows(rows) {
  var images = []
  var seen = {}
  var paths = String(rows || "").split("\n")

  for (var i = 0; i < paths.length; i++) {
    var row = paths[i]
    if (!row) continue

    var columns = row.split("\t")
    var path = columns[0]
    if (!path) continue

    var fileName = path.split("/").pop()
    if (seen[fileName]) continue
    seen[fileName] = true

    images.push({
      filePath: path,
      fileName: fileName,
      thumbnailPath: columns[1] || path,
      displayName: columns[2] || ""
    })
  }

  return images
}

function itemMatches(images, index, filterText) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var needle = String(filterText || "").toLowerCase()
  if (!needle) return true

  var path = String(images[index].filePath || "")
  return nameForPath(path).toLowerCase().indexOf(needle) !== -1
      || labelForPath(path).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText) {
  if (!filterText) return index

  var position = 0
  for (var i = 0; i < index; i++) {
    if (itemMatches(images, i, filterText)) position++
  }

  return position
}

function selectedFilteredPosition(images, selectedIndex, filterText) {
  if (!filterText) return selectedIndex
  return itemMatches(images, selectedIndex, filterText) ? filteredPosition(images, selectedIndex, filterText) : 0
}

function indexForSelectedImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].filePath === selectedImage) return i
  }

  return 0
}

function nextSelectedIndexForFilter(images, selectedIndex, filterText) {
  if (itemMatches(images, selectedIndex, filterText)) return selectedIndex
  return firstMatchingIndex(images, filterText)
}

if (typeof module !== "undefined") {
  module.exports = {
    nameForPath: nameForPath,
    labelForPath: labelForPath,
    labelForImage: labelForImage,
    loadRows: loadRows,
    itemMatches: itemMatches,
    firstMatchingIndex: firstMatchingIndex,
    filteredPosition: filteredPosition,
    selectedFilteredPosition: selectedFilteredPosition,
    indexForSelectedImage: indexForSelectedImage,
    nextSelectedIndexForFilter: nextSelectedIndexForFilter
  }
}
