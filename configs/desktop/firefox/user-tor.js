// chrome and dialogs only: nothing here reaches web content or tor browser's fingerprint
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("widget.wayland.opaque-region.enabled", false);
// the xdg portal's file picker, as every other app; the portal sees only the paths picked
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
