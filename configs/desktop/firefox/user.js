user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// without this the wayland surface is marked opaque and userChrome.css alpha never shows
user_pref("widget.wayland.opaque-region.enabled", false);

user_pref("browser.startup.homepage", "file://@HOME@/.config/qutebrowser/startpage.html");
user_pref("browser.startup.page", 1);
user_pref("security.fileuri.strict_origin_policy", true);

// machine-wide prefs go in policies.json or mozilla.cfg: this file misses profiles made after the last config run
