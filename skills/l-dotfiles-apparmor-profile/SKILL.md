---
name: l-dotfiles-apparmor-profile
description: Writing or adjusting an AppArmor profile or local/ drop-in in configs/base/apparmor, loading it, reading denials, apparmor.test.nu, and the enforce vs complain policy. Load when an app is blocked by AppArmor or a new app needs confinement.
---

# apparmor-profile

Built on apparmor.d (`aa-install`). Files in `configs/base/apparmor/`:

- `profiles.conf`: every deployed profile and its mode, a row `<name> <mode>[,flags]`. apparmor.d's profiles by name,
  plus the module's own. `,flags` only for apparmor.d's profiles: an own profile keeps its flags in its `profile` line,
  and `mod.nu` writes this row's mode into it.
- `profiles/<name>`: own profiles where apparmor.d has none, plus own copies of apparmor.d's firefox, thunderbird and
  libreoffice (`OVERRIDES` in `apparmor.test.nu`). First line `# managed by arch-dotfiles/apparmor`, then
  `profile <name> <attachment> flags=(...)` (usually `@{exec_path}`), listed in `profiles.conf`. The test fails once
  apparmor.d starts shipping one that is no override.
- `local/<name>`: extra rules for an apparmor.d profile, installed to `/etc/apparmor.d/local/<name>`. The name must
  be in `profiles.conf`.
- `abstractions/`: shared rules, installed as `abstractions/dotfiles/<name>`.

## Policy

Everything that opens other people's content (browsers, mail, chat, media, documents, images, archives, the
`child-open*` openers) is `enforce`; `apparmor.test.nu` has the list and fails otherwise. To back one off on a
single machine use `aa complain <profile>` (from `aa.nu`, writes `/etc/apparmor/*/manual.conf`, survives config
runs), never the baseline; `aa enforce` and `aa off` likewise. `aa` alone shows loaded profiles and modes,
`aa list [filter]` apparmor.d's profile names.

## Fix a denial

1. Reproduce, then read the kernel log (no auditd; `sysctl-apparmor.conf` raises the rate limit):
   ```bash
   journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail
   ```
   Note `profile=`, `operation=`, `name=`, `requested_mask=`. An app launched only to trigger the denial goes on
   the agent's own headless output (skill `l-dotfiles-gui-testing`).
2. Add the narrowest rule to `local/<profile>` (or `profiles/<profile>`), with a one-line comment above it only when the rule looks removable and isn't.
   Prefer an existing abstraction (`include <abstractions/dotfiles/viewer-read>`).
3. Compile check without root:
   ```bash
   configs/base/apparmor/apparmor.test.nu
   ```
   Exit 0 is clean; the "Failed to create cache" warnings are expected.
4. Load it: Luca runs `dot apply --system` (the module's `system` verb installs and reloads, then fails if any
   profile is not in its expected mode). An agent runs `DOT_SYSTEM=skip dot apply`, which records the system part as
   pending (exit 3), and asks him. The verb does nothing on WSL, and installs the profiles only once
   `/etc/apparmor.d/abstractions/base-strict` exists. For a quick loop on a `local/` rule Luca can run
   `sudo install -m644 configs/base/apparmor/local/<p> /etc/apparmor.d/local/<p> && sudo apparmor_parser -r /etc/apparmor.d/<p>`
   (`<p>.apparmor.d` where apparmor.d replaced a stock profile); `dot apply --system` must still be run so it is
   reproducible.
5. Retry the app and recheck the log. `dot test lint` runs the same test.
