pragma Singleton
import QtQuick

QtObject {
  function none() { return flat("transparent", 0) }

  function flat(color, width) {
    var w = Number(width)
    return { color: color || "transparent", width: isFinite(w) && w > 0 ? w : 0 }
  }

  // a control's border in one of its states: normal, hover-cursor, focus or selected
  function controlSpec(state, foreground, accent) {
    var s = state === "focus" ? [Style.focusStateColor(foreground, accent), Style.focusBorderAlpha, Style.focusBorderWidth]
      : state === "hover-cursor" ? [Style.hoverStateColor(foreground, accent), Style.hoverBorderAlpha, Style.hoverBorderWidth]
      : state === "selected" ? [Style.selectedMarkColor(foreground, accent), Style.selectedBorderAlpha, Style.selectedBorderWidth]
      : [Style.normalStateColor(foreground, accent), Style.normalBorderAlpha, Style.normalBorderWidth]
    return flat(Util.alpha(s[0], s[1]), s[2])
  }

  function width(spec) { return spec ? spec.width : 0 }
  function color(spec) { return spec ? spec.color : "transparent" }
}
