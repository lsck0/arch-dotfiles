import QtQuick
import qs.Commons

BarIconButton {
  id: root

  property string moduleName: ""
  property var settings: ({})
  property string activeText: ""
  property string inactiveText: activeText
  property string activeTooltipText: ""
  property string inactiveTooltipText: activeTooltipText
  property string indicatorBlock: "single"
  property var indicatorHost: null
  property var activeOverride: null
  readonly property bool effectiveActive: activeOverride === null || activeOverride === undefined ? active : activeOverride === true
  readonly property bool belongsInBlock: indicatorBlock === "active" ? effectiveActive : (indicatorBlock === "inactive" ? !effectiveActive : true)
  readonly property bool inactiveRevealed: !effectiveActive && !!indicatorHost && indicatorHost.revealInactiveIndicators

  function extractData(raw) {
    return Util.parseModuleJson(raw)
  }

  function syncIndicatorOpacity() {
    root.opacity = !belongsInBlock ? 0 : (effectiveActive ? 1 : (inactiveRevealed ? 0.45 : 0))
  }

  Component.onCompleted: syncIndicatorOpacity()
  onActiveChanged: syncIndicatorOpacity()
  onEffectiveActiveChanged: syncIndicatorOpacity()
  onBarChanged: syncIndicatorOpacity()
  onBelongsInBlockChanged: syncIndicatorOpacity()
  onInactiveRevealedChanged: syncIndicatorOpacity()
  onIndicatorBlockChanged: syncIndicatorOpacity()

  // Fully hide (and stop reserving layout space for) an indicator that is
  // concealed. `keepSpace` only matters for the hover-reveal-while-off
  // mechanism (`inactiveRevealed`), which this repo's indicators cannot
  // reach: `indicatorHost` is never set here (see Indicators.qml's header),
  // so `inactiveRevealed` is always false and every currently-off indicator
  // was concealed AND still reserving its statusSlot width forever — the
  // dead space in the bar's right cluster whenever DND/keep-awake are off
  // or the reminder/pomodoro binaries aren't installed. QtQuick.Layouts
  // excludes invisible items from layout, so this also fixes the width.
  visible: belongsInBlock && !concealed && (text !== "" || keepSpace)
  text: effectiveActive ? activeText : inactiveText
  tooltipText: effectiveActive ? activeTooltipText : inactiveTooltipText
  keepSpace: true
  dimmed: !effectiveActive
  concealed: !effectiveActive && !inactiveRevealed
  interactive: belongsInBlock && (effectiveActive || indicatorBlock === "inactive" || inactiveRevealed)
  useActiveColor: false
  // maintainIndicatorReveal/revealHost dropped: this repo's WidgetButton.qml
  // is a "trimmed from omarchy-shell" local original that never had these
  // two properties (a hover-reveal-while-area-hovered mechanism for the
  // full dynamic Indicators cluster upstream builds — not ported here,
  // see Indicators.qml's own header comment). indicatorHost stays null in
  // this repo's simplified Indicators.qml, so inactiveRevealed is always
  // false regardless — removing these two assignments changes nothing
  // this repo's indicators actually use, just the QML error they threw
  // the first time BarIndicator was ever actually instantiated (Phase 1
  // never exercised this file live, only checked it loaded inert).
  fontSize: Style.font.caption
  horizontalMargin: 5
  verticalPadding: 5
  fixedWidth: vertical ? -1 : Style.bar.statusSlot
  fixedHeight: vertical ? Style.bar.statusSlot : -1
}
