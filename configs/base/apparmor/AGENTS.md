# base/apparmor

Writing or adjusting profiles, reading denials: `l-dotfiles-apparmor-profile`.

- `profiles.conf`: the mode table for every profile, apparmor.d's and our own.
- `profiles/`: own profiles (installed as `<name>.dotfiles`), for apps apparmor.d lacks. `OVERRIDES` in `mod.nu`
  installs apparmor.d's `firefox`, `thunderbird`, `libreoffice`, `browserpass` the
  same way, generated from the installed profile with a `/usr/...` attachment in place of the nested optional-usr
  `/{{,usr/}...}` one (apparmor 4.1.8 can't attach that form).
- `local/`: drop-ins on apparmor.d profiles and the `child-open*` openers; `abstractions/`: shared fragments.
- A rule names the repo checkout as `@{DOTFILES}`, which `tunables` in `mod.nu` defines; the test fails on a spelled-out
  `projects/arch-dotfiles`.
- Everything that opens other people's content stays `enforce`; the test fails otherwise. A confined program may only
  exec into a loaded profile.
- Back off on one machine with `aa complain|off <profile>` (never in the baseline); `aa enforce` re-confines.
- `./apparmor.test.nu` (part of lint) parses with `--skip-cache`, so it needs no root.
