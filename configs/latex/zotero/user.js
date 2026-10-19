user_pref("extensions.zotero.httpServer.localAPI.enabled", true);
// dot drops better bibtex into the profile: profile-scope addons load without a prompt, and stay at the pinned version
user_pref("extensions.autoDisableScopes", 14);
user_pref("extensions.update.enabled", false);
user_pref("extensions.zotero.translators.better-bibtex.autoExport.@EXPORT_KEY@", @EXPORT_JOB@);
