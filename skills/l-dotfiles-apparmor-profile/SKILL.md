---
name: l-dotfiles-apparmor-profile
description: Writing or adjusting an AppArmor profile or local/ drop-in in configs/base/apparmor, loading it, reading denials, apparmor.test.nu, and the enforce vs complain policy. Load when an app is blocked by AppArmor or a new app needs confinement.
---

# apparmor-profile

Built on apparmor.d (`aa-install`). In `configs/base/apparmor/`:

- `profiles.conf`: every deployed profile, `<name> <mode>[,flags]`. `,flags` only for apparmor.d's; an own profile keeps
  flags in its `profile` line and `mod.nu` writes the mode into it.
- `profiles/<name>`: own profiles, plus own copies of apparmor.d's firefox, thunderbird, libreoffice (`OVERRIDES` in
  `apparmor.test.nu`). First line `# managed by arch-dotfiles/apparmor`, then `profile <name> <attachment>
  flags=(...)`. The test fails once apparmor.d ships one that is no override.
- `local/<name>`: extra rules for an apparmor.d profile (`/etc/apparmor.d/local/<name>`); the name must be in
  `profiles.conf`.
- `abstractions/`: installed as `abstractions/dotfiles/<name>`.

## Policy

Everything that opens other people's content (browsers, mail, chat, media, documents, images, archives, `child-open*`)
is `enforce`; `apparmor.test.nu` fails otherwise. Back one off on one machine with `aa complain <profile>` (writes
`/etc/apparmor/*/manual.conf`, survives runs), never in the baseline; likewise `aa enforce`, `aa off`. `aa` shows
loaded modes, `aa list [filter]` apparmor.d's names.

## Fix a denial

1. Reproduce (on a headless output, `l-dotfiles-gui-testing`), then read
   `journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail`: `profile=`, `operation=`, `name=`, `requested_mask=`.
2. Add the narrowest rule to `local/<profile>` or `profiles/<profile>`; prefer an abstraction
   (`include <abstractions/dotfiles/viewer-read>`).
3. `configs/base/apparmor/apparmor.test.nu`: exit 0 is clean; "Failed to create cache" warnings are expected.
4. Load: an agent runs `DOT_SYSTEM=skip dot apply` (pending, exit 3) and asks Luca for `dot apply --system`, which
   installs, reloads and fails if a profile is not in its mode. Does nothing on WSL; needs
   `/etc/apparmor.d/abstractions/base-strict`. Quick loop for Luca:
   `sudo install -m644 configs/base/apparmor/local/<p> /etc/apparmor.d/local/<p> && sudo apparmor_parser -r /etc/apparmor.d/<file>`
   where `<file>` is `<p>.dotfiles` for an own profile (in `profiles/`), else `<p>.apparmor.d` if it exists, else `<p>`.
   Never reload the bare `<p>` of an own profile: it is the stock unconfined stub and replaces the enforced one.
   Then still `dot apply --system`.
5. Retry and recheck the log.
