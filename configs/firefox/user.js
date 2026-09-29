user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// reuse qutebrowser's start page
user_pref("browser.startup.homepage", "file:///home/luca/.config/qutebrowser/startpage.html");
user_pref("browser.startup.page", 1);
// let the start page load ~/.cache/wal assets
user_pref("security.fileuri.strict_origin_policy", false);

// 4 blocks tracker cookies; 5 partitions storage and broke teams screen share
user_pref("browser.contentblocking.category", "custom");
user_pref("network.cookie.cookieBehavior", 4);
