user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// one file picker everywhere: the xdg portal's (gtk), not the one inside the app
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);

user_pref("mail.openpgp.allow_external_gnupg", true);
user_pref("mail.openpgp.fetch_pubkeys_from_gnupg", true);

user_pref("mailnews.message_display.disable_remote_image", true);
user_pref("mailnews.headers.sendUserAgent", false);
user_pref("mail.inline_attachments", false);

user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("mailnews.start_page.enabled", false);

user_pref("extensions.activeThemeID", "default-theme@mozilla.org");
user_pref("ui.systemUsesDarkTheme", @DARK@);

// new mail is announced by the shell toast, which do-not-disturb silences; thunderbird's own chime ignores it
user_pref("mail.biff.play_sound", false);
