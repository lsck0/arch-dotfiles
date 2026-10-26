# base/apparmor

Writing or adjusting profiles, reading denials: `l-dotfiles-apparmor-profile`.

- `profiles.conf`: the mode table for every profile, apparmor.d's and our own.
- `profiles/`: own profiles (installed as `<name>.dotfiles`), for apps apparmor.d lacks, plus copies of apparmor.d's
  `firefox`, `thunderbird`, `libreoffice` with a plain `/usr` attachment (apparmor 4.1.8 can't attach their brace
  form). `apparmor.test.nu` fails when a copy's body drifts from upstream.
- `local/`: drop-ins on apparmor.d profiles and the `child-open*` openers; `abstractions/`: shared fragments.
- Everything that opens other people's content stays `enforce`; the test fails otherwise. A confined program may only
  exec into a loaded profile.
- Back off on one machine with `aa complain|off <profile>` (never in the baseline); `aa enforce` re-confines.
- `./apparmor.test.nu` (part of lint): "Failed to create cache" warnings are expected without root.
