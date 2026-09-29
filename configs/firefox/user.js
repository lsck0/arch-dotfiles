user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Homepage + new windows: reuse qutebrowser's matrix start page (shared file).
user_pref("browser.startup.homepage", "file:///home/luca/.config/qutebrowser/startpage.html");
user_pref("browser.startup.page", 1);
// New tabs cannot point to a file natively (pref removed in FF61); needs a "new tab override" addon.
// Let the file:// start page load its ../../.cache/wal assets (wallpaper bg + wal CSS), else Firefox blocks cross-dir file resources.
user_pref("security.fileuri.strict_origin_policy", false);

// Reject known trackers (ETP standard) instead of accepting all cookies. Total
// cookie protection (5) partitions third-party storage and broke zscaler/Teams
// screen share; 4 blocks tracker cookies without partitioning, so Teams works.
user_pref("browser.contentblocking.category", "custom");
user_pref("network.cookie.cookieBehavior", 4);
