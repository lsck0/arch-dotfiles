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

function hex2(v) {
  var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
  return s.length < 2 ? "0" + s : s
}

function hexOf(c) {
  return "#" + hex2(c.r) + hex2(c.g) + hex2(c.b)
}

function luma(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

function saturation(c) {
  var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b)
  return max <= 0 ? 0 : (max - min) / max
}

// hue in degrees, 0 for greys
function hueOf(c) {
  var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), d = max - min
  if (d <= 0) return 0
  var h = max === c.r ? ((c.g - c.b) / d) % 6 : max === c.g ? (c.b - c.r) / d + 2 : (c.r - c.g) / d + 4
  return (h * 60 + 360) % 360
}

function redDistance(c) {
  var h = hueOf(c)
  return Math.min(h, 360 - h)
}

/**
 * Quantized wallpaper colours ({r, g, b} in 0..1) to a wallust-shaped colors.json object for
 * Color.conditionPalette: darkest is background, lightest foreground, the most saturated colour4
 * (accent), the reddest colour1 (urgent), a mid grey colour8 (muted), the rest colour2-6.
 * A preview only: wallust's own pick can differ. Fewer than 3 colours gives {}.
 */
function rawFromSwatches(swatches) {
  var list = []
  for (var i = 0; i < (swatches || []).length; i++) {
    var s = swatches[i]
    if (s && isFinite(s.r) && isFinite(s.g) && isFinite(s.b)) list.push({ r: s.r, g: s.g, b: s.b })
  }
  if (list.length < 3) return {}
  list.sort(function(a, b) { return luma(a) - luma(b) })
  var bg = list[0], fg = list[list.length - 1]
  var mids = list.slice(1, list.length - 1)
  var bySat = mids.slice().sort(function(a, b) { return saturation(b) - saturation(a) })
  var accent = bySat[0] || fg
  var muted = bySat[bySat.length - 1] || bg
  var urgent = mids.slice().sort(function(a, b) { return redDistance(a) - redDistance(b) })[0] || accent
  var colors = { color1: hexOf(urgent), color4: hexOf(accent), color8: hexOf(muted) }
  var slots = ["color2", "color3", "color5", "color6"]
  for (var k = 0; k < slots.length && k + 1 < bySat.length; k++) colors[slots[k]] = hexOf(bySat[k + 1])
  return { special: { background: hexOf(bg), foreground: hexOf(fg) }, colors: colors }
}
