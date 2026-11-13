.pragma library

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
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

function entryAcronym(entry) {
  return wordText([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
    .split(/[^a-z0-9]+/).filter(Boolean).map(function(w) { return w.charAt(0) }).join("")
}

function termMatches(entry, term) {
  return !term || entrySearchText(entry).indexOf(term) >= 0 || (term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0)
}

function allTermsMatch(entry, query) {
  return String(query || "").toLowerCase().trim().split(/\s+/).every(function(t) { return termMatches(entry, t) })
}

var TIER_NAME_PREFIX = 6
var TIER_ID_PREFIX = 5
var TIER_NAME_OR_ID = 4
var TIER_HAYSTACK = 3
var TIER_ACRONYM = 2
var TIER_TERMS = 1

// tier: how the query matched, ranked above frecency; score: the finer order inside a tier. null when it does not match
function entryMatch(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return { tier: 0, score: 0 }
  if (!allTermsMatch(entry, q)) return null

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return { tier: TIER_NAME_PREFIX, score: -name.length }
  if (directId === 0) return { tier: TIER_ID_PREFIX, score: -id.length }
  if (directName > 0) return { tier: TIER_NAME_OR_ID, score: -directName * 10 - name.length }
  if (directId > 0) return { tier: TIER_NAME_OR_ID, score: -directId * 10 - id.length }

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return { tier: TIER_HAYSTACK, score: -hayIndex }

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex >= 0) return { tier: TIER_ACRONYM, score: -acronymIndex * 10 - acronym.length }

  return { tier: TIER_TERMS, score: -name.length }
}

// match tier first, then frecency, then the fine score, then the name
function sortedEntries(values, query, hiddenCallback, rankCallback) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var match = entryMatch(entry, q)
    if (!match) continue
    rows.push({ entry: entry, tier: match.tier, score: match.score, rank: rankCallback ? rankCallback(entry) : 0, key: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (a.tier !== b.tier) return b.tier - a.tier
    if (a.rank !== b.rank) return b.rank - a.rank
    if (a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    return 0
  })

  return rows.map(function(r) { return r.entry })
}

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

function frecencyBump(map, id, now) {
  var next = Object.assign({}, map)
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
