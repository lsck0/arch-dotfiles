.pragma library

function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function titleCase(name) {
  return name.replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function labelForImage(image) {
  return titleCase(image.displayName || nameForPath(image.filePath))
}

function loadRows(rows) {
  var images = []
  var seen = {}
  var paths = String(rows || "").split("\n")

  for (var i = 0; i < paths.length; i++) {
    var columns = paths[i].split("\t")
    var path = columns[0]
    if (!path) continue

    var fileName = path.split("/").pop()
    if (seen[fileName]) continue
    seen[fileName] = true

    images.push({
      filePath: path,
      thumbnailPath: columns[1] || path,
      displayName: columns[2] || "",
      artist: columns[3] || ""
    })
  }

  return images
}

// What applying a row hands to dot theme, and what it is recalled by: a theme's name, else the wallpaper's path.
function pickFor(image) {
  return image.displayName || image.filePath
}

// Every word occurs in the file name, the theme name or the artist, in any order.
function matches(image, words) {
  var text = (nameForPath(image.filePath) + " " + image.displayName + " " + image.artist).toLowerCase().replace(/[-_]+/g, " ")
  return words.every(function(word) { return text.indexOf(word) !== -1 })
}

// The row a pick names; the first when none does.
function indexOfPick(images, pick) {
  return Math.max(0, images.findIndex(function(image) { return pickFor(image) === pick }))
}

// list.nu recent's rows: "<theme|wallpaper>\t<pick>\t<thumb>\t<the theme's palette as json>"
function loadRecent(rows) {
  return String(rows || "").split("\n").filter(Boolean).map(function(row) {
    var columns = row.split("\t")
    var palette = null
    try {
      palette = columns[3] ? JSON.parse(columns[3]) : null
    } catch (e) {}
    return { kind: columns[0], pick: columns[1], thumbnailPath: columns[2], label: titleCase(nameForPath(columns[1])), palette: palette }
  })
}

// The recent tiles left to right, each with its slot: per kind the newest `shown` picks other than the one in effect
// (current: [wallpaper, theme]), wallpapers before themes.
function recentTiles(recent, current, shown) {
  function last(kind, inEffect) {
    return recent.filter(function(entry) { return entry.kind === kind && entry.pick !== inEffect }).slice(0, shown)
  }
  return last("wallpaper", current[0]).concat(last("theme", current[1]))
    .map(function(entry, slot) { return Object.assign({}, entry, { slot: slot }) })
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
