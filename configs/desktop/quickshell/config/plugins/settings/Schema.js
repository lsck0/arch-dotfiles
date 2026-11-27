.pragma library

// the machine's platform file, which dot set --json lists beside the modules and dot set takes as platform.<key>
const machineId = "platform"
const machineLabel = "MACHINE"
const togglesId = ":toggles"
const togglesLabel = "QUICK TOGGLES"
const systemId = ":system"
const systemLabel = "SYSTEM"
// what the window runs of dot itself; a terminal one may ask for sudo, a key touch or package removals
const systemActions = [
  { name: "update", detail: "dot sync", args: ["sync"], terminal: true },
  { name: "apply", detail: "dot apply --user", args: ["apply", "--user"], terminal: false },
  { name: "apply system", detail: "dot apply --system", args: ["apply", "--system"], terminal: true },
  { name: "packages", detail: "dot apply --packages", args: ["apply", "--packages"], terminal: true }
]
// what the window opens of the shell itself, under the keys that open it too (hyprland_keybindings.lua); words are
// what a newcomer may search for it by
const launchers = [
  { name: "keybinds", detail: "SUPER+F1", words: ["keybindings", "shortcuts", "hotkeys", "keys", "help"],
    ipc: ["appsearch", "openWith", "? "] },
  { name: "wallpaper", detail: "SUPER+CTRL+W", words: ["wallpapers", "background"], bin: ["wallpaper-picker"] },
  { name: "theme", detail: "SUPER+SHIFT+W", words: ["themes", "colors", "palette"], bin: ["wallpaper-picker", "--themes"] }
]
const driftChoices = ["adopt", "reset"]
const segmentedMax = 4
const choicePageSize = 30
// a platform key's packages waits for dot apply --packages, its apply for a whole dot apply
const applyOrder = ["live", "packages", "relink", "apply", "relogin", "reboot"]
const filesizeUnits = { "": 1, b: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 }
// a search phrase also searched as what the options call it: a newcomer's word the labels and docs never use
const synonyms = { "caps lock": "nocaps", "timeout": "idle", "startup": "autostart", "printer": "printing" }
// a field's share of a term's score: labels and keys whole, the module less, docs less again, enum values and toggle
// states least, so a hit in the label leads
const weights = { name: 1, context: 0.6, prose: 0.5, value: 0.25 }
// scattered letters may skip at most this many per letter after the first, so "dpi" fits no "desktop_quotes_file"
const fuzzyGaps = 3
const filesizeShown = [["TiB", 1099511627776], ["GiB", 1073741824], ["MiB", 1048576], ["KiB", 1024]]

function typeOf(option) {
  var type = String(option.type || "").replace(/\?$/, "")
  if (option.fixed) return "fixed"
  // an ordered list is a sequence: a pick appends, and may repeat (a bar's separators)
  if ((option.choices || []).length > 0) return !/^list</.test(type) ? "enum" : option.ordered ? "sequence" : "multi"
  if (["bool", "int", "float", "path", "string", "filesize"].indexOf(type) >= 0) return type
  if (/^list<(string|path|int|float)>$/.test(type)) return "list"
  return "json"
}

function moduleNormalize(module) {
  return Object.assign({}, module, {
    options: (module.options || []).map(function (o) { return Object.assign({}, o, { nuType: o.type, type: typeOf(o) }) })
  })
}

function resettable(option) {
  return option.type !== "fixed" && option.source === (option.scope === "machine" ? "platform" : "profile")
}

function notes(text) {
  return String(text || "").split("\n").filter(function (l) { return /(^|: )note: /.test(l) })
    .map(function (l) { return l.slice(l.indexOf("note:") + "note:".length).trim() })
}

function optionId(module, option) { return module.name + "." + option.key }

function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

function moduleLabel(module) { return module.label || module.name }

function segmented(option) { return option.type === "enum" && (option.choices || []).length <= segmentedMax }

// how well one query term fits a text, -1 when not at all: the whole text beats a substring, which beats scattered
// letters, at a word start more, earlier more; scattered (fuzzy) letters, only where fuzzy is set, stay inside one word
// and start at its first letter (so "light" never fits "playwright"), scoring less the wider they spread
function termScore(term, text, fuzzy) {
  var hay = String(text === undefined || text === null ? "" : text).toLowerCase()
  if (hay === term) return 4000
  var at = hay.indexOf(term)
  if (at >= 0) return 2000 - Math.min(at, 500) + (at === 0 || /[^a-z0-9]/.test(hay[at - 1]) ? 1000 : 0)
  if (!fuzzy) return -1
  var best = -1
  var offset = 0
  var words = hay.split(/([\s\/.]+)/)
  for (let w = 0; w < words.length; offset += words[w].length, w++) {
    let word = words[w]
    if (word[0] !== term[0]) continue
    let gaps = 0
    let last = 0
    for (let i = 1; i < term.length && last >= 0; i++) {
      let next = word.indexOf(term[i], last + 1)
      if (next >= 0) gaps += next - last - 1
      last = next
    }
    if (last >= 0 && gaps <= fuzzyGaps * (term.length - 1)) best = Math.max(best, Math.max(1, 1000 - gaps * 10 - Math.min(offset, 500)))
  }
  return best
}

// a search's fields by kind, each [text, weight, fuzzy]: names (labels, keys, ids) fuzzily, the rest only as a substring,
// since scattered letters fit nearly any sentence
function fields(names, context, prose, values) {
  var out = []
  var add = function (list, weight, fuzzy) { (list || []).forEach(function (t) { out.push([t, weight, fuzzy]) }) }
  add(names, weights.name, true)
  add(context, weights.context, false)
  add(prose, weights.prose, false)
  add(values, weights.value, false)
  return out
}

// needle, then needle with each synonym phrase in it replaced, whole words only
function variants(needle) {
  var out = [needle]
  for (let key in synonyms) {
    let phrase = new RegExp("(^|\\s)" + key + "(?=\\s|$)")
    out = out.concat(out.filter(function (v) { return phrase.test(v) }).map(function (v) { return v.replace(phrase, "$1" + synonyms[key]) }))
  }
  return out
}

// every whitespace-separated term of needle fits some field, needle or one of its synonym variants: the summed best
// weighted scores, -1 for no match; fuzzy false keeps scattered letters out
function matchScore(needle, list, fuzzy) {
  var forms = variants(String(needle).toLowerCase().trim())
  var total = -1
  for (let v = 0; v < forms.length; v++) {
    let terms = forms[v].split(/\s+/).filter(function (t) { return t !== "" })
    let sum = 0
    for (let t = 0; t < terms.length && sum >= 0; t++) {
      let best = -1
      for (let f = 0; f < list.length; f++) {
        let score = termScore(terms[t], list[f][0], list[f][2] && fuzzy !== false)
        if (score >= 0) best = Math.max(best, score * list[f][1])
      }
      sum = best < 0 ? -1 : sum + best
    }
    total = Math.max(total, sum)
  }
  return total
}

function contains(needle, list, fuzzy) { return matchScore(needle, list, fuzzy) >= 0 }

// an enum's values, as stored and as shown
function valueWords(option) {
  if (option.type !== "enum") return []
  return (option.choices || []).map(function (c) { return String(c) }).concat((option.choices || []).map(function (c) { return choiceLabel(option, c) }))
}

function optionScore(needle, module, option, fuzzy) {
  return matchScore(needle, fields([option.label, option.key, option.group], [module.name, module.label], [option.doc], valueWords(option)), fuzzy)
}

function optionMatches(needle, module, option, fuzzy) { return optionScore(needle, module, option, fuzzy) >= 0 }

// a multi-state toggle's states are searchable ("dark" finds the theme mode), a switch's off and on are not
function toggleMatches(needle, toggle, fuzzy) {
  var states = toggleIsSwitch(toggle) ? [] : toggle.states || []
  return contains(needle, fields([toggle.label, toggle.name], [togglesLabel], [], states), fuzzy)
}

function toggleOptionMatches(needle, toggle, option, fuzzy) {
  return contains(needle, fields([option.label, option.key], [toggle.name, togglesLabel], [option.doc], valueWords(option)), fuzzy)
}

function launchEntries(needle, fuzzy) {
  var hits = launchers.filter(function (l) {
    return !needle || contains(needle, fields([l.name].concat(l.words), [togglesLabel], [l.detail]), fuzzy)
  }).map(function (l) { return Object.assign({ kind: "launch", id: togglesId + ".open." + l.name }, l) })
  return hits.length > 0 ? [{ kind: "header", id: "#" + togglesId + "/open", text: "open" }].concat(hits) : []
}

// scattered letters count only while nothing fits needle as a word or substring: "dpi" lists Wine dpi alone
function fuzzyAllowed(modules, toggles, needle, status, machine) {
  var entry = function (r) { return r.kind !== "header" }
  if (toggleEntries(toggles, needle, false).some(entry) || launchEntries(needle, false).some(entry)) return false
  if (systemEntries(status, needle, false).some(entry)) return false
  return !(machine ? [machine] : []).concat(modules).some(function (m) {
    return (m.options || []).some(function (o) { return optionMatches(needle, m, o, false) })
  })
}

// the entries that match, best first; equal scores keep their order
function ranked(list, score) {
  return list.map(function (item, i) { return { item: item, i: i, score: score(item) } })
    .filter(function (e) { return e.score >= 0 })
    .sort(function (a, b) { return b.score - a.score || a.i - b.i })
    .map(function (e) { return e.item })
}

function moduleGroup(module) { var i = module.name.indexOf("/"); return i < 0 ? "" : module.name.slice(0, i) }

function sectionLabel(module) {
  if (module.label && module.label !== module.name) return module.label
  var group = moduleGroup(module)
  return group ? module.name.slice(group.length + 1) : module.name
}

// a section with nothing to list is left out: System until dot status answers, a module without options; a search
// keeps every section and only zeroes the counts, so the list keeps its indices while the query changes
function sections(modules, toggles, query, status, machine) {
  var needle = query.trim().toLowerCase()
  var fuzzy = !needle || fuzzyAllowed(modules, toggles, needle, status, machine)
  var out = (machine ? [{
    kind: "section",
    id: machineId,
    label: machineLabel,
    count: (machine.options || []).filter(function (o) { return !needle || optionMatches(needle, machine, o, fuzzy) }).length
  }] : []).concat([{
    kind: "section",
    id: togglesId,
    label: togglesLabel,
    count: toggleEntries(toggles, needle, fuzzy).concat(launchEntries(needle, fuzzy)).filter(function (r) { return r.kind !== "header" }).length
  }, {
    kind: "section",
    id: systemId,
    label: systemLabel,
    count: systemEntries(status, needle, fuzzy).filter(function (r) { return r.kind !== "header" }).length
  }].filter(function (s) { return s.id !== systemId || status }))
  // a module outside any group (scripts, skills) comes first, under no header, beside MACHINE and the others
  var group = ""
  var key = function (m) { return (moduleGroup(m) ? "1" : "0") + m.name }
  var sorted = modules.slice().sort(function (a, b) { return key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0 })
  for (let m = 0; m < sorted.length; m++) {
    let module = sorted[m]
    let options = module.options || []
    if (options.length === 0) continue
    let g = moduleGroup(module)
    if (g !== group) { out.push({ kind: "header", id: "#" + g, label: g }); group = g }
    out.push({
      kind: "section",
      id: module.name,
      label: sectionLabel(module),
      count: needle ? options.filter(function (o) { return optionMatches(needle, module, o, fuzzy) }).length : options.length
    })
  }
  return out
}

// title: what the row shows instead of the option's label, a search's "proxychains Enabled" among several Enabled
function optionRow(module, option, title) {
  var row = { kind: "option", id: optionId(module, option), option: option }
  if (title) row.title = title
  return row
}

function toggleIsSwitch(toggle) { return (toggle.states || []).length === 2 && toggle.states[0] === "off" && toggle.states[1] === "on" }

function toggleRow(toggle) { return { kind: "toggle", id: togglesId + "." + toggle.name, toggle: toggle } }

function toggleOptionRow(toggle, option) {
  return {
    kind: "option",
    id: togglesId + "." + toggle.name + "." + option.key,
    option: Object.assign({ apply: "live", source: "toggle", toggle: toggle.name }, option, { nuType: option.type, type: typeOf(option) })
  }
}

function toggleLabel(toggle) { return String(toggle.label || toggle.name) }

function toggleEntries(toggles, needle, fuzzy) {
  var plain = []
  var grouped = []
  // by what the row shows, not the script name: "Hear OBS output" files as obs-listen
  var sorted = toggles.slice().sort(function (a, b) { return toggleLabel(a).localeCompare(toggleLabel(b)) })
  for (let t = 0; t < sorted.length; t++) {
    let toggle = sorted[t]
    if (!toggle.available) continue
    if ((toggle.options || []).length === 0) {
      if (!needle || toggleMatches(needle, toggle, fuzzy)) plain.push(toggleRow(toggle))
      continue
    }
    let options = toggle.options.filter(function (o) { return !needle || toggleOptionMatches(needle, toggle, o, fuzzy) })
    if (options.length > 0) grouped.push({ kind: "header", id: "#" + togglesId + "/" + toggle.name, text: toggleLabel(toggle) })
    for (let o = 0; o < options.length; o++) grouped.push(toggleOptionRow(toggle, options[o]))
  }
  return plain.concat(grouped)
}

// dot status --json as rows: the actions, each managed file edited since its apply, then the checks, failing first
function systemEntries(status, needle, fuzzy) {
  if (!status) return needle ? [] : [{ kind: "header", id: "#" + systemId + "/loading", text: "status loading" }]
  var checks = (status.checks || []).map(function (c) {
    return { kind: "check", id: systemId + ".check." + c.check, level: String(c.level), name: c.check, text: c.text }
  })
  var pending = (status.migrations_pending || []).map(function (m) {
    return { kind: "check", id: systemId + ".migration." + m, level: "pending", name: "migration", text: m }
  }).concat((status.system_pending || []).map(function (p) {
    return { kind: "check", id: systemId + ".system." + p, level: "pending", name: "system", text: p }
  })).concat((status.pending_apply || []).map(function (d) {
    return { kind: "check", id: systemId + ".pending." + d.target, level: "pending", name: d.module, text: d.target + " :: " + d.drift }
  }))
  var actions = systemActions.map(function (a) { return Object.assign({ kind: "action", id: systemId + ".action." + a.name }, a) })
  var drifted = status.drift || []
  var drift = drifted.map(function (d) {
    return { kind: "drift", id: systemId + ".drift." + d.target, module: d.module, target: d.target, drift: d.drift }
  })
  var match = function (r) {
    return !needle || contains(needle, fields([r.name, r.module, r.level], [systemLabel], [r.text, r.detail, r.target]), fuzzy)
  }
  var out = []
  var passed = function (c) { return c.level === "ok" ? 1 : 0 }
  checks.sort(function (a, b) { return passed(a) - passed(b) })
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

// a module's options under its group headers, the groups in the order their first option comes
function moduleRows(module) {
  var out = []
  var groups = []
  var byGroup = ({})
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
  return out
}

function rows(modules, toggles, sectionId, query, status, machine) {
  var needle = query.trim().toLowerCase()
  var out = []
  if (needle) {
    let fuzzy = fuzzyAllowed(modules, toggles, needle, status, machine)
    let labelled = (machine ? [Object.assign({}, machine, { label: machineLabel })] : []).concat(modules)
    let hits = toggleEntries(toggles, needle, fuzzy).concat(launchEntries(needle, fuzzy))
    if (hits.length > 0) out.push({ kind: "header", id: "#" + togglesId, text: togglesLabel })
    out = out.concat(hits)
    out = out.concat(systemEntries(status, needle, fuzzy))
    // the module with the best hit first, so Enter or a change right after typing acts on the closest option
    let groups = ranked(labelled.map(function (module) {
      let scored = ranked((module.options || []).map(function (o) { return { option: o, score: optionScore(needle, module, o, fuzzy) } }),
        function (e) { return e.score })
      return { module: module, scored: scored }
    }), function (g) { return g.scored.length > 0 ? g.scored[0].score : -1 })
    // a label several modules' hits share ("Enabled") is shown with its module's name
    let owners = ({})
    groups.forEach(function (g) {
      g.scored.forEach(function (e) {
        let label = String(e.option.label || e.option.key)
        owners[label] = (owners[label] || []).concat(owners[label] && owners[label].indexOf(g.module.name) >= 0 ? [] : [g.module.name])
      })
    })
    for (let g = 0; g < groups.length; g++) {
      let module = groups[g].module
      out.push({ kind: "header", id: "#" + module.name, text: moduleLabel(module) })
      for (let o = 0; o < groups[g].scored.length; o++) {
        let option = groups[g].scored[o].option
        let label = String(option.label || option.key)
        out.push(optionRow(module, option, owners[label].length > 1 ? sectionLabel(module) + " " + label : ""))
      }
    }
    return out
  }
  if (sectionId === machineId) return machine ? moduleRows(machine) : []
  if (sectionId === togglesId) return toggleEntries(toggles, "").concat(launchEntries(""))
  if (sectionId === systemId) return systemEntries(status, "")
  var module = modules.find(function (m) { return m.name === sectionId })
  return module ? moduleRows(module) : []
}

function selectable(list, index, direction) {
  for (let i = index; i >= 0 && i < list.length; i += direction)
    if (list[i].kind !== "header") return i
  return -1
}

function decimals(option) {
  var size = step(option)
  return size >= 1 ? 0 : Math.min(6, Math.ceil(-Math.log10(size) - 1e-9))
}

function snap(option, n) {
  if (bounded(option.min)) n = Math.max(Number(option.min), n)
  if (bounded(option.max)) n = Math.min(Number(option.max), n)
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

// a list option's new entry from its text, by the element type: a number for list<int> and list<float>; undefined when
// the text is no such entry
function listEntry(option, text) {
  var entry = String(text).trim()
  var element = (String(option.nuType || "").match(/^list<(\w+)>/) || [])[1]
  if (element !== "int" && element !== "float") return entry === "" ? undefined : entry
  var n = Number(entry)
  return entry === "" || !isFinite(n) || (element === "int" && !Number.isInteger(n)) ? undefined : n
}

function encode(option, value) {
  // a cleared nullable option unsets; Number(null) would store 0b
  if (value === undefined || value === null) return "null"
  if (option.type === "filesize") return Number(value) + "b"
  return JSON.stringify(value === undefined ? null : value)
}

function toggleArgument(option, value) {
  if (option.type === "list" || option.type === "json") return JSON.stringify(value === undefined ? null : value)
  if (option.type === "bool") return value ? "true" : "false"
  return String(value)
}

// a multi-select's value with choice switched, in the value's own order with a new one last; a sequence's with choice
// appended; an enum's is the choice
function choicePicked(option, value, choice) {
  if (option.type === "sequence") return (value || []).concat([choice])
  if (option.type !== "multi") return choice
  var list = (value || []).slice()
  var at = list.indexOf(choice)
  if (at >= 0 && option.nonempty && list.length === 1) return list
  if (at >= 0) list.splice(at, 1)
  else list.push(choice)
  // the saved order first, then the choices': switching one off and on again gives the saved value back, not pending
  var saved = option.value || []
  var choices = option.choices || []
  function rank(c) { var i = saved.indexOf(c); return i >= 0 ? i : saved.length + choices.indexOf(c) }
  return list.sort(function (a, b) { return rank(a) - rank(b) })
}

// a choice as the window shows it: its choice_labels name (an extension id's), else the choice itself
function choiceLabel(option, choice) {
  var labels = option.choice_labels || ({})
  if (Object.prototype.hasOwnProperty.call(labels, String(choice))) return String(labels[String(choice)])
  return choice === "" ? "(none)" : String(choice)
}

function choicesMatching(option, filter) {
  if (filter === "") return option.choices || []
  return ranked(option.choices || [], function (c) { return matchScore(filter, fields([choiceLabel(option, c), c])) })
}

function choicePageStart(cursor) { return Math.max(0, Math.floor(cursor / choicePageSize) * choicePageSize) }

function strongestApply(options) {
  var at = 0
  for (let i = 0; i < options.length; i++) at = Math.max(at, applyOrder.indexOf(options[i].apply))
  return at > 0 ? applyOrder[at] : ""
}
