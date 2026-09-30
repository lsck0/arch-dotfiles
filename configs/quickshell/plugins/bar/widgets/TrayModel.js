.pragma library

function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

// localsend's tray item adds nothing over share > receive
function hiddenByDefault(item) {
  return itemNamed(item, "localsend")
}
