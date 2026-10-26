.pragma library

const togglesId = ":toggles"
const togglesLabel = "Quick toggles"
const systemId = ":system"
const systemLabel = "System"
// what the window runs of dot itself; a terminal one may ask for sudo, a key touch or package removals
const systemActions = [
  { name: "update", detail: "dot sync: pull, install, apply, commit", args: ["sync"], terminal: true },
  { name: "apply", detail: "dot apply --user", args: ["apply", "--user"], terminal: false },
  { name: "apply system", detail: "dot apply --system", args: ["apply", "--system"], terminal: true },
  { name: "packages", detail: "dot apply --packages", args: ["apply", "--packages"], terminal: true }
]
const driftChoices = ["adopt", "reset"]
const segmentedMax = 4
const choicePageSize = 30
const applyOrder = ["live", "relink", "relogin", "reboot"]
const filesizeUnits = { "": 1, b: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 }
const filesizeShown = [["TiB", 1099511627776], ["GiB", 1073741824], ["MiB", 1048576], ["KiB", 1024]]

function typeOf(option) {
  var type = String(option.type || "").replace(/\?$/, "")
  if ((option.choices || []).length > 0) return "enum"
  if (["bool", "int", "float", "path", "string", "filesize"].indexOf(type) >= 0) return type
  if (/^list<(string|path|int|float)>$/.test(type)) return "list"
  return "json"
}

function moduleNormalize(module) {
  return Object.assign({}, module, {
    options: (module.options || []).map(function (o) { return Object.assign({}, o, { nuType: o.type, type: typeOf(o) }) })
  })
}

function resettable(option) { return option.source === (option.scope === "machine" ? "platform" : "profile") }

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

function moduleGroup(module) { var i = module.name.indexOf("/"); return i < 0 ? "" : module.name.slice(0, i) }

function sectionLabel(module) {
  if (module.label && module.label !== module.name) return module.label
  var group = moduleGroup(module)
  return group ? module.name.slice(group.length + 1) : module.name
}

function sections(modules, toggles, query, status) {
  var needle = query.trim().toLowerCase()
  var out = [{
    kind: "section",
    id: togglesId,
    label: togglesLabel,
    count: toggleEntries(toggles, needle).filter(function (r) { return r.kind !== "header" }).length
  }, {
    kind: "section",
    id: systemId,
    label: systemLabel,
    count: systemEntries(status, needle).filter(function (r) { return r.kind !== "header" }).length
  }]
  var group = null
  var sorted = modules.slice().sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
  for (let m = 0; m < sorted.length; m++) {
    let module = sorted[m]
    let options = module.options || []
    let g = moduleGroup(module)
    if (g !== group) { out.push({ kind: "header", id: "#" + g, label: g }); group = g }
    out.push({
      kind: "section",
      id: module.name,
      label: sectionLabel(module),
      count: needle ? options.filter(function (o) { return optionMatches(needle, module, o) }).length : options.length
    })
  }
  return out
}

function optionRow(module, option) {
  return { kind: "option", id: optionId(module, option), option: option }
}

function toggleIsSwitch(toggle) { return toggle.states.length === 2 && toggle.states[0] === "off" && toggle.states[1] === "on" }

function toggleRow(toggle) { return { kind: "toggle", id: togglesId + "." + toggle.name, toggle: toggle } }

function toggleOptionRow(toggle, option) {
  return {
    kind: "option",
    id: togglesId + "." + toggle.name + "." + option.key,
    option: Object.assign({ apply: "live", source: "toggle", toggle: toggle.name }, option, { nuType: option.type, type: typeOf(option) })
  }
}

function toggleLabel(toggle) { return String(toggle.label || toggle.name) }

function toggleEntries(toggles, needle) {
  var plain = []
  var grouped = []
  // by what the row shows, not the script name: "Hear OBS output" files as obs-listen
  var sorted = toggles.slice().sort(function (a, b) { return toggleLabel(a).localeCompare(toggleLabel(b)) })
  for (let t = 0; t < sorted.length; t++) {
    let toggle = sorted[t]
    if (!toggle.available) continue
    if ((toggle.options || []).length === 0) {
      if (!needle || toggleMatches(needle, toggle)) plain.push(toggleRow(toggle))
      continue
    }
    let options = toggle.options.filter(function (o) { return !needle || toggleOptionMatches(needle, toggle, o) })
    if (options.length > 0) grouped.push({ kind: "header", id: "#" + togglesId + "/" + toggle.name, text: toggleLabel(toggle) })
    for (let o = 0; o < options.length; o++) grouped.push(toggleOptionRow(toggle, options[o]))
  }
  return plain.concat(grouped)
}

// dot status --json as rows: the actions, each managed file edited since its apply, then the checks, failing first
function systemEntries(status, needle) {
  if (!status) return needle ? [] : [{ kind: "header", id: "#" + systemId + "/loading", text: "status loading" }]
  var checks = (status.checks || []).map(function (c) {
    return { kind: "check", id: systemId + ".check." + c.check, level: String(c.level), name: c.check, text: c.text }
  })
  var pending = (status.migrations_pending || []).map(function (m) {
    return { kind: "check", id: systemId + ".migration." + m, level: "pending", name: "migration", text: m + " runs with the next dot sync" }
  }).concat((status.system_pending || []).map(function (p) {
    return { kind: "check", id: systemId + ".system." + p, level: "pending", name: "system", text: p + ": apply system runs it" }
  })).concat((status.pending_apply || []).map(function (d) {
    return { kind: "check", id: systemId + ".pending." + d.target, level: "pending", name: d.module, text: d.target + " (" + d.drift + "): apply puts it back" }
  }))
  var actions = systemActions.map(function (a) { return Object.assign({ kind: "action", id: systemId + ".action." + a.name }, a) })
  var drifted = status.drift || []
  var drift = drifted.map(function (d) {
    return { kind: "drift", id: systemId + ".drift." + d.target, module: d.module, target: d.target, drift: d.drift }
  })
  var match = function (r) { return !needle || contains(needle, [r.name, r.text, r.detail, r.module, r.target, r.level, systemLabel]) }
  var out = []
  var failing = function (c) { return c.level === "ok" ? 1 : 0 }
  checks.sort(function (a, b) { return failing(a) - failing(b) })
  var groups = [["actions", actions], ["edited since apply", drift],
    ["status", [{ kind: "check", id: systemId + ".generation", level: "info", name: "generation", text: status.generation || "" }]
      .concat(pending, checks)]]
  for (let g = 0; g < groups.length; g++) {
    let hits = groups[g][1].filter(match)
    if (hits.length === 0) continue
    out.push({ kind: "header", id: "#" + systemId + "/" + groups[g][0], text: groups[g][0] })
    out = out.concat(hits)
  }
  return out
}

function checkFailed(row) { return row.level === "FAIL" }

// an adopt is followed by an apply, which records the file as the module's output again
function systemCommand(dot, row, choice) {
  if (row.kind === "action") return [dot].concat(row.args)
  if (row.kind === "drift" && choice === "reset") return [dot, "module", "reset", row.target]
  if (row.kind === "drift") {
    return ["sh", "-c", '"$0" module adopt "$1" || exit; "$0" apply "$2"; r=$?; [ $r -eq 3 ] && exit 0; exit $r', dot, row.target, row.module]
  }
  return []
}

// a terminal that stays until a key, so the run's last lines and any prompt stay readable
function terminalCommand(argv, label) {
  var quoted = argv.map(function (a) { return "'" + String(a).replace(/'/g, "'\\''") + "'" }).join(" ")
  return ["app2unit", "-T", "--", "bash", "-c", quoted + "; echo; read -rsn1 -p '" + label + " finished, any key closes'"]
}

function rows(modules, toggles, sectionId, query, status) {
  var needle = query.trim().toLowerCase()
  var out = []
  if (needle) {
    let hits = toggleEntries(toggles, needle)
    if (hits.length > 0) out.push({ kind: "header", id: "#" + togglesId, text: togglesLabel })
    out = out.concat(hits)
    out = out.concat(systemEntries(status, needle))
    for (let m = 0; m < modules.length; m++) {
      let module = modules[m]
      let matched = (module.options || []).filter(function (o) { return optionMatches(needle, module, o) })
      if (matched.length > 0) out.push({ kind: "header", id: "#" + module.name, text: moduleLabel(module) })
      for (let o = 0; o < matched.length; o++) out.push(optionRow(module, matched[o]))
    }
    return out
  }
  if (sectionId === togglesId) return toggleEntries(toggles, "")
  if (sectionId === systemId) return systemEntries(status, "")
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

function selectable(list, index, direction) {
  for (let i = index; i >= 0 && i < list.length; i += direction)
    if (list[i].kind !== "header") return i
  return -1
}

function decimals(option) {
  var step = Number(option.step) || (option.type === "int" ? 1 : 0.01)
  return step >= 1 ? 0 : Math.min(6, Math.ceil(-Math.log10(step) - 1e-9))
}

function snap(option, n) {
  if (option.min !== undefined && option.min !== null) n = Math.max(Number(option.min), n)
  if (option.max !== undefined && option.max !== null) n = Math.min(Number(option.max), n)
  return option.type === "int" ? Math.round(n) : Number(n.toFixed(decimals(option)))
}

function step(option) { return Number(option.step) || (option.type === "int" ? 1 : 0.01) }

function bounded(value) { return value !== undefined && value !== null }

function sliderable(option) {
  return (option.type === "int" || option.type === "float") && bounded(option.min) && bounded(option.max)
}

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

function filesizeText(bytes) {
  var n = Number(bytes)
  for (let i = 0; i < filesizeShown.length; i++)
    if (n >= filesizeShown[i][1] && n % filesizeShown[i][1] === 0) return n / filesizeShown[i][1] + filesizeShown[i][0]
  return n + "B"
}

function filesizeParse(text) {
  var m = String(text).trim().toLowerCase().match(/^(\d+(?:\.\d+)?)\s*([kmgt]i?b|b)?$/)
  return m ? Math.round(Number(m[1]) * filesizeUnits[m[2] || ""]) : undefined
}

function toText(option, value) {
  if (value === undefined || value === null) return ""
  if (option.type === "int" || option.type === "float") return Number(value).toFixed(decimals(option))
  if (option.type === "filesize") return filesizeText(value)
  if (option.type === "list") return ""
  if (option.type === "json") return JSON.stringify(value)
  return String(value)
}

function fromText(option, text) {
  if (/\?$/.test(option.nuType || "") && String(text).trim() === "") return null
  if (option.type === "int" || option.type === "float") {
    let n = Number(String(text).trim())
    return String(text).trim() === "" || !isFinite(n) ? undefined : snap(option, n)
  }
  if (option.type === "filesize") return filesizeParse(text)
  if (option.type === "json") {
    try { return JSON.parse(text) } catch (e) { return undefined }
  }
  return String(text)
}

function encode(option, value) {
  if (option.type === "filesize") return Number(value) + "b"
  return JSON.stringify(value === undefined ? null : value)
}

function toggleArgument(option, value) {
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

function strongestApply(options) {
  var at = 0
  for (let i = 0; i < options.length; i++) at = Math.max(at, applyOrder.indexOf(options[i].apply))
  return at > 0 ? applyOrder[at] : ""
}
