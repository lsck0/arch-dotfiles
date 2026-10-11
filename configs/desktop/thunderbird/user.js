user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// one key for everything: the system gnupg keyring and gpg-agent, so yubikey and pinentry work as in the shell
user_pref("mail.openpgp.allow_external_gnupg", true);
user_pref("mail.openpgp.fetch_pubkeys_from_gnupg", true);

// no remote content or tracking pixels in mail
user_pref("mailnews.message_display.disable_remote_image", true);
user_pref("mailnews.headers.sendUserAgent", false);
user_pref("mail.inline_attachments", false);

// no telemetry, studies or start page
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("mailnews.start_page.enabled", false);

// follow the wal-coloured gtk theme
user_pref("extensions.activeThemeID", "default-theme@mozilla.org");
user_pref("ui.systemUsesDarkTheme", 1);
