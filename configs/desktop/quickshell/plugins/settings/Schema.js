.pragma library

// the sidebar entry of the toggles; ':' never occurs in a module name
const togglesId = ":toggles"
const togglesLabel = "Quick toggles"
// an enum with at most this many choices is a chip row, a longer one a list that opens on enter
const segmentedMax = 4
// an open list shows its choices a page at a time, so thousands (font families) stay one screen
const choicePageSize = 30
// what an apply needs after the write, weakest first
const applyOrder = ["live", "relink", "relogin", "reboot"]

// choices make an enum, a list of scalars a list of entries, anything structured is edited as json
function typeOf(option) {
  var type = String(option.type || "").replace(/\?$/, "")
  if ((option.choices || []).length > 0) return "enum"
  if (["bool", "int", "float", "path", "string"].indexOf(type) >= 0) return type
  if (/^list<(string|path|int|float)>$/.test(type)) return "list"
  return "json"
}

function moduleNormalize(module) {
  return Object.assign({}, module, {
    options: (module.options || []).map(function (o) { return Object.assign({}, o, { nuType: o.type, type: typeOf(o) }) })
  })
}

// only a value this window wrote can be dropped: the profile's for a user option, the platform's for a machine one
function resettable(option) { return option.source === (option.scope === "machine" ? "platform" : "profile") }

// the `note:` lines of a dot run's output, what it asks of the person (a relogin, a pending system part);
// log-record writes them to stderr as "<tag>: note: <text>"
function notes(text) {
  return String(text || "").split("\n").filter(function (l) { return /(^|: )note: /.test(l) })
    .map(function (l) { return l.slice(l.indexOf("note:") + "note:".length).trim() })
}

function optionId(module, option) { return module.name + "." + option.key }

function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

function moduleLabel(module) { return module.label || module.name }

function segmented(option) { return option.type === "enum" && (option.choices || []).length <= segmentedMax }

function contains(needle, fields) {
  for (let i = 0; i < fields.length; i++)
    if (String(fields[i] || "").toLowerCase().indexOf(needle) >= 0) return true
  return false
}

function optionMatches(needle, module, option) {
  return contains(needle, [option.label, option.key, option.doc, option.group, module.name, module.label])
}

function toggleMatches(needle, toggle) { return contains(needle, [toggle.label, toggle.name, togglesLabel]) }

function toggleOptionMatches(needle, toggle, option) {
  return contains(needle, [option.label, option.key, option.doc, toggle.name, togglesLabel])
}

// [{id, label, count}]; count is the match count while searching, else the entry size
function sections(modules, toggles, query) {
  var needle = query.trim().toLowerCase()
  var out = [{
    id: togglesId,
    label: togglesLabel,
    count: toggleEntries(toggles, needle).filter(function (r) { return r.kind !== "header" }).length
  }]
  for (let m = 0; m < modules.length; m++) {
    let module = modules[m]
    let options = module.options || []
    out.push({
      id: module.name,
      label: moduleLabel(module),
      count: needle ? options.filter(function (o) { return optionMatches(needle, module, o) }).length : options.length
    })
  }
  return out
}

function optionRow(module, option) {
  return { kind: "option", id: optionId(module, option), option: option }
}

function toggleRow(toggle) { return { kind: "toggle", id: togglesId + "." + toggle.name, toggle: toggle } }

// set through the toggle's own verb (option.set) instead of `dot set`, and always live
function toggleOptionRow(toggle, option) {
  return {
    kind: "option",
    id: togglesId + "." + toggle.name + "." + option.key,
    option: Object.assign({ apply: "live", source: "toggle", toggle: toggle.name }, option, { nuType: option.type, type: typeOf(option) })
  }
}

// plain toggles first: one with options becomes a header over its option rows, and a header claims every row below it
function toggleEntries(toggles, needle) {
  var plain = []
  var grouped = []
  for (let t = 0; t < toggles.length; t++) {
    let toggle = toggles[t]
    if ((toggle.options || []).length === 0) {
      if (!needle || toggleMatches(needle, toggle)) plain.push(toggleRow(toggle))
      continue
    }
    let options = toggle.options.filter(function (o) { return !needle || toggleOptionMatches(needle, toggle, o) })
    if (options.length > 0) grouped.push({ kind: "header", id: "#" + togglesId + "/" + toggle.name, text: toggle.name })
    for (let o = 0; o < options.length; o++) grouped.push(toggleOptionRow(toggle, options[o]))
  }
  return plain.concat(grouped)
}

// headers interleaved with option and toggle rows: one entry's groups, or every match grouped by entry while searching
function rows(modules, toggles, sectionId, query) {
  var needle = query.trim().toLowerCase()
  var out = []
  if (needle) {
    let hits = toggleEntries(toggles, needle)
    if (hits.length > 0) out.push({ kind: "header", id: "#" + togglesId, text: togglesLabel })
    out = out.concat(hits)
    for (let m = 0; m < modules.length; m++) {
      let module = modules[m]
      let matched = (module.options || []).filter(function (o) { return optionMatches(needle, module, o) })
      if (matched.length > 0) out.push({ kind: "header", id: "#" + module.name, text: moduleLabel(module) })
      for (let o = 0; o < matched.length; o++) out.push(optionRow(module, matched[o]))
    }
    return out
  }
  if (sectionId === togglesId) return toggleEntries(toggles, "")
  for (let m = 0; m < modules.length; m++) {
    let module = modules[m]
    if (module.name !== sectionId) continue
    let groups = []
    let byGroup = ({})
    for (let o = 0; o < (module.options || []).length; o++) {
      let option = module.options[o]
      let group = option.group || ""
      if (!(group in byGroup)) { byGroup[group] = []; groups.push(group) }
      byGroup[group].push(option)
    }
    for (let g = 0; g < groups.length; g++) {
      if (groups[g]) out.push({ kind: "header", id: "#" + module.name + "/" + groups[g], text: groups[g] })
      for (let o = 0; o < byGroup[groups[g]].length; o++) out.push(optionRow(module, byGroup[groups[g]][o]))
    }
  }
  return out
}

// the nearest selectable row from index in direction (1 or -1), index itself included; -1 if none
function selectable(list, index, direction) {
  for (let i = index; i >= 0 && i < list.length; i += direction)
    if (list[i].kind !== "header") return i
  return -1
}

function decimals(option) {
  var step = Number(option.step) || (option.type === "int" ? 1 : 0.01)
  return step >= 1 ? 0 : Math.min(6, Math.ceil(-Math.log10(step) - 1e-9))
}

// clamped to min/max and rounded to the step's precision
function snap(option, n) {
  if (option.min !== undefined && option.min !== null) n = Math.max(Number(option.min), n)
  if (option.max !== undefined && option.max !== null) n = Math.min(Number(option.max), n)
  return option.type === "int" ? Math.round(n) : Number(n.toFixed(decimals(option)))
}

function step(option) { return Number(option.step) || (option.type === "int" ? 1 : 0.01) }

// the value one Left (-1) or Right (1) away, undefined for a type that does not step
function adjusted(option, value, direction) {
  if (option.type === "bool") return direction > 0
  if (option.type === "int" || option.type === "float") return snap(option, Number(value) + direction * step(option))
  if (option.type === "enum") {
    let choices = option.choices || []
    if (choices.length === 0) return undefined
    let at = choices.indexOf(value)
    return choices[(Math.max(0, at) + direction + choices.length) % choices.length]
  }
  return undefined
}

function toText(option, value) {
  if (value === undefined || value === null) return ""
  if (option.type === "int" || option.type === "float") return Number(value).toFixed(decimals(option))
  if (option.type === "list") return ""
  if (option.type === "json") return JSON.stringify(value)
  return String(value)
}

// the typed value of a text field, undefined when it does not parse
function fromText(option, text) {
  if (option.type === "int" || option.type === "float") {
    let n = Number(String(text).trim())
    return String(text).trim() === "" || !isFinite(n) ? undefined : snap(option, n)
  }
  if (option.type === "json") {
    try { return JSON.parse(text) } catch (e) { return undefined }
  }
  return String(text)
}

// the value argument of `set`: lists as JSON, everything else as its plain text
function encode(option, value) {
  if (option.type === "list" || option.type === "json") return JSON.stringify(value === undefined ? null : value)
  if (option.type === "bool") return value ? "true" : "false"
  return String(value)
}

function choiceLabel(choice) { return choice === "" ? "(none)" : String(choice) }

function choicesMatching(option, filter) {
  var needle = filter.toLowerCase()
  return (option.choices || []).filter(function (c) { return choiceLabel(c).toLowerCase().indexOf(needle) >= 0 })
}

function choicePageStart(cursor) { return Math.max(0, Math.floor(cursor / choicePageSize) * choicePageSize) }

// the strongest need of a set of options, "" when all are live
function strongestApply(options) {
  var at = 0
  for (let i = 0; i < options.length; i++) at = Math.max(at, applyOrder.indexOf(options[i].apply))
  return at > 0 ? applyOrder[at] : ""
}
