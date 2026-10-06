.pragma library

// adapted from omarchy-shell
function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function titleCase(name) {
  return name.replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function labelForPath(path) {
  return titleCase(nameForPath(path))
}

// themes mode labels by theme name, not wallpaper file
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
      thumbnailPath: columns[1] || path,
      displayName: columns[2] || ""
    })
  }

  return images
}

function indexForSelectedImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].filePath === selectedImage) return i
  }

  return 0
}
