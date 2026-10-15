user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// without this the wayland surface is marked opaque and userChrome.css alpha never shows
user_pref("widget.wayland.opaque-region.enabled", false);

// reuse qutebrowser's start page, mozilla.cfg points the new tab there too
user_pref("browser.startup.homepage", "file://@HOME@/.config/qutebrowser/startpage.html");
user_pref("browser.startup.page", 1);
user_pref("security.fileuri.strict_origin_policy", true);

// telemetry, tracking protection, cookies, https-only and dns are machine-wide in policies.json and mozilla.cfg,
// which reach every profile; this file only reaches the ones that existed at the last config run
