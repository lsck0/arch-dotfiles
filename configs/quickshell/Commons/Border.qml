pragma Singleton
import QtQuick
import "BorderGeometry.js" as Geometry

// Border-spec factory. A spec carries a colour plus per-side widths, which
// is what lets BorderSurface pick between the cheap native Rectangle.border
// path and the Shape-ring path.
//
// Same shape as omarchy-shell's Border.qml minus its shell.toml-driven
// per-surface/per-theme override resolution: this repo has one look, so a
// spec's colour/width is just what the caller passes (usually a
// Color.<surface>.* role already derived from pywal), with no override
// lookup layer on top.
//
// Upstream's gradient field is kept in the spec object because
// BorderGeometry.js and BorderOverlay.qml still read it, but nothing in this
// repo ever enables it — see Ui/BorderOverlay.qml's note.
QtObject {
  id: root

  function none() {
    return flat("transparent", 0)
  }

  function flat(color, width) {
    return {
      color: color || "transparent",
      widths: Geometry.parseWidthSpec(width, 0),
      gradient: { colors: [], angle: 0, enabled: false },
    }
  }

  // A per-instance colour override if one was given, otherwise the surface
  // default. Was `localOrSurfaceSpec(section, token, local, default, width)`
  // — the first two arguments were never read, and both branches produced
  // the same width, so all it did was pick between two colours.
  function surfaceSpec(localColor, defaultColor, width) {
    var chosen = (localColor === undefined || localColor === null) ? defaultColor : localColor
    return flat(chosen, width)
  }

  // Interactive-state border specs, resolved through Style's state engine so
  // controls in the kit share one ladder. `accent` lets a caller redirect
  // the selected/focus role at a non-default palette colour (a destructive
  // button passes its urgent colour here).
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

  function withWidth(spec, width) {
    if (!spec) return flat("transparent", 0)
    return { color: spec.color, gradient: spec.gradient, widths: Geometry.parseWidthSpec(width, 0) }
  }

  function isNone(spec) { return !spec || Geometry.maxWidth(spec.widths) <= 0 }
  function needsOverlay(spec) { return Geometry.needsOverlay(spec) }
  function canUseNative(spec) { return Geometry.canUseNative(spec) }
  function top(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function right(spec) { return spec && spec.widths ? spec.widths.right : 0 }
  function bottom(spec) { return spec && spec.widths ? spec.widths.bottom : 0 }
  function left(spec) { return spec && spec.widths ? spec.widths.left : 0 }
  function uniformWidth(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function color(spec) { return spec ? spec.color : "transparent" }
}
