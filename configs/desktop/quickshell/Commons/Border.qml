pragma Singleton
import QtQuick

// uniform border specs { color, width } for BorderSurface
QtObject {
  id: root

  function none() {
    return flat("transparent", 0)
  }

  function flat(color, width) {
    var w = Number(width)
    return { color: color || "transparent", width: isFinite(w) && w > 0 ? w : 0 }
  }

  function controlColor(prefix, foreground, accent) {
    if (prefix === "focus") return Style.focusStateColor(foreground, accent)
    if (prefix === "hover-cursor") return Style.hoverStateColor(foreground, accent)
    if (prefix === "selected") return Style.selectedStateColor(foreground, accent)
    return Style.normalStateColor(foreground, accent)
  }

  function controlAlpha(prefix) {
    if (prefix === "focus") return Style.focusBorderAlpha
    if (prefix === "hover-cursor") return Style.hoverBorderAlpha
    if (prefix === "selected") return Style.selectedBorderAlpha
    return Style.normalBorderAlpha
  }

  function controlWidth(prefix) {
    if (prefix === "focus") return Style.focusBorderWidth
    if (prefix === "hover-cursor") return Style.hoverBorderWidth
    if (prefix === "selected") return Style.selectedBorderWidth
    return Style.normalBorderWidth
  }

  function controlSpec(state, foreground, accent) {
    var prefix = (state === "hover" || state === "hot") ? "hover-cursor" : (state || "normal")
    var color = Util.alpha(controlColor(prefix, foreground, accent), controlAlpha(prefix))
    return flat(color, controlWidth(prefix))
  }

  function width(spec) { return spec ? spec.width : 0 }
  function color(spec) { return spec ? spec.color : "transparent" }
}
