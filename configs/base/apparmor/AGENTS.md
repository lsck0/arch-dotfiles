# base/apparmor

Profiles, drop-ins, denials, the enforce policy and `aa`: `l-dotfiles-apparmor-profile`. Layout only here:

- `config/profiles.conf`: the mode table; `config/profiles/`: own profiles (`<name>.dotfiles`); `config/local/`:
  drop-ins on apparmor.d profiles and the `child-open*` openers; `config/abstractions/`: shared fragments
  (`deny-exec-later` closes what shells and tools source or run later).
- `mod.nu`: `tunables` defines `@{DOTFILES}`; `OVERRIDES` regenerates apparmor.d profiles whose nested optional-usr
  attachment apparmor 4.1.8 cannot attach.
- `./apparmor.test.nu` (part of lint) parses with `--skip-cache`, so it needs no root.
