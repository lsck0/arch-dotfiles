pragma Singleton
import QtQuick
import Quickshell

// The shell's options link writes into prefs.json (prefs-config in mod.nu). A missing file or key keeps the default,
// today's behaviour.
QtObject {
  id: root

  property bool motion: true
  property bool glitch: true
  property bool desktopQuote: true
  property string desktopQuotesFile: ""
  property bool desktopAgenda: true
  property bool lockMedia: true
  property bool lockNotifications: true
  property string notificationPosition: "right"
  property bool barSpectrum: true

  property WatchedFile file: WatchedFile {
    path: Quickshell.shellDir + "/prefs.json"
    blockLoading: true
    onLoaded: root.apply(Util.parseObject(text()))
  }

  function apply(prefs) {
    const flag = (key, fallback) => typeof prefs[key] === "boolean" ? prefs[key] : fallback
    root.motion = flag("motion", true)
    root.glitch = flag("glitch", true)
    root.desktopQuote = flag("desktopQuote", true)
    root.desktopQuotesFile = typeof prefs.desktopQuotesFile === "string" ? prefs.desktopQuotesFile : ""
    root.desktopAgenda = flag("desktopAgenda", true)
    root.lockMedia = flag("lockMedia", true)
    root.lockNotifications = flag("lockNotifications", true)
    root.notificationPosition = prefs.notificationPosition === "left" ? "left" : "right"
    root.barSpectrum = flag("barSpectrum", true)
  }
}
