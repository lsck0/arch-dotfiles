user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// reuse qutebrowser's start page, mozilla.cfg points the new tab there too
user_pref("browser.startup.homepage", "file://@HOME@/.config/qutebrowser/startpage.html");
user_pref("browser.startup.page", 1);
user_pref("security.fileuri.strict_origin_policy", true);

// 4 blocks tracker cookies; 5 partitions storage and broke teams screen share
user_pref("browser.contentblocking.category", "custom");
user_pref("network.cookie.cookieBehavior", 4);

// no telemetry, studies or sponsored content
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);

// full telemetry off (healthreport/usage above don't cover these), no normandy experiments, no pocket.
// DoH/TRR deliberately left off: homelab hosts (search.lsck0.dev etc.) resolve internally and DoH would bypass that.
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("extensions.pocket.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
