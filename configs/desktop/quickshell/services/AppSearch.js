.pragma library

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function entrySortKey(entry) {
  return entryName(entry).toLowerCase()
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function") return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true

  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - name.length
}

// rankCallback(entry) >= 0 (frecency) breaks score ties, and orders the empty query
function sortedEntries(values, query, hiddenCallback, rankCallback) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var score = fuzzyScore(entry, q)
    if (score < 0) continue
    rows.push({ entry: entry, score: score, rank: rankCallback ? rankCallback(entry) : 0,
                key: entrySortKey(entry), name: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.rank !== b.rank) return b.rank - a.rank
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  // unwrap: callers expect DesktopEntry objects, not sort rows
  var out = []
  for (var r = 0; r < rows.length; r++) out.push(rows[r].entry)
  return out
}

// frecency: launch count weighted by recency; buckets in ms
var FRECENCY_BUCKETS = [[86400000, 4], [604800000, 2], [2592000000, 1]]
var FRECENCY_STALE_WEIGHT = 0.5
var FRECENCY_MAX_ENTRIES = 200

function frecencyRank(record, now) {
  if (!record || !(record.n > 0)) return 0
  var age = Math.max(0, now - (Number(record.t) || 0))
  for (var i = 0; i < FRECENCY_BUCKETS.length; i++)
    if (age < FRECENCY_BUCKETS[i][0]) return record.n * FRECENCY_BUCKETS[i][1]
  return record.n * FRECENCY_STALE_WEIGHT
}

// copy with id bumped, trimmed to the most recent FRECENCY_MAX_ENTRIES
function frecencyBump(map, id, now) {
  var next = {}
  for (var k in map) next[k] = map[k]
  var prev = next[id]
  next[id] = { n: (prev && prev.n > 0 ? prev.n : 0) + 1, t: now }
  var keys = Object.keys(next)
  if (keys.length > FRECENCY_MAX_ENTRIES) {
    keys.sort(function(a, b) { return (next[b].t || 0) - (next[a].t || 0) })
    for (var i = FRECENCY_MAX_ENTRIES; i < keys.length; i++) delete next[keys[i]]
  }
  return next
}

function escapeHtml(value) {
  return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// indices of query chars in text: the substring when present, else a greedy subsequence, else []
function matchIndices(text, query) {
  var t = String(text || "").toLowerCase()
  var q = String(query || "").toLowerCase().replace(/\s+/g, "")
  var out = []
  if (!q) return out
  var at = t.indexOf(q)
  if (at >= 0) {
    for (var i = 0; i < q.length; i++) out.push(at + i)
    return out
  }
  var j = 0
  for (var k = 0; k < t.length && j < q.length; k++) {
    if (t.charAt(k) === q.charAt(j)) { out.push(k); j++ }
  }
  return j === q.length ? out : []
}

// StyledText with matched chars in color and bold
function highlight(text, query, color) {
  var s = String(text || "")
  var hits = matchIndices(s, query)
  if (hits.length === 0) return escapeHtml(s)
  var set = {}
  for (var i = 0; i < hits.length; i++) set[hits[i]] = true
  var out = ""
  for (var k = 0; k < s.length; k++) {
    var ch = escapeHtml(s.charAt(k))
    out += set[k] ? "<b><font color=\"" + color + "\">" + ch + "</font></b>" : ch
  }
  return out
}
