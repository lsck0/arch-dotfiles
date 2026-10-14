---
name: l-dotfiles-apparmor-profile
description: Writing or adjusting an AppArmor profile or local/ drop-in in configs/base/apparmor, loading it, reading denials, apparmor.test.nu, and the enforce vs complain policy. Load when an app is blocked by AppArmor or a new app needs confinement.
---

# apparmor-profile

Built on apparmor.d (`aa-install`). Files in `configs/base/apparmor/`:

- `profiles.conf`: every deployed profile and its mode (`<name> enforce[,flag]`). apparmor.d's profiles by name,
  plus the module's own.
- `profiles/<name>`: own profiles where apparmor.d has none. First line `# managed by arch-dotfiles/apparmor`, a
  `profile <name> @{exec_path} flags=(...)` line, listed in `profiles.conf`.
- `local/<name>`: extra rules for an apparmor.d profile, installed to `/etc/apparmor.d/local/<name>`. The name must
  be in `profiles.conf`.
- `abstractions/`: shared rules, installed as `abstractions/dotfiles/<name>`.

## Policy

Everything that opens other people's content (browsers, mail, chat, media, documents, images, archives, the
`child-open*` openers) is `enforce`; `apparmor.test.nu` has the list and fails otherwise. To back one off on a
single machine use `aa complain <profile>` (from `aa.nu`, writes `/etc/apparmor/*/manual.conf`, survives config
runs), never the baseline. `aa` alone shows loaded profiles and modes.

## Fix a denial

1. Reproduce, then read the kernel log (no auditd; `sysctl-apparmor.conf` raises the rate limit):
   ```bash
   journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail
   ```
   Note `profile=`, `operation=`, `name=`, `requested_mask=`. When an agent launches the confined app only to
   trigger the denial (not because the user is watching it), put its window on a headless output the user never
   sees (`hyprctl output create headless` -> HEADLESS-N, launch/move it there, then `hyprctl output remove
   HEADLESS-N`), not a visible workspace (AGENTS.md gotchas).
2. Add the narrowest rule to `local/<profile>` (or `profiles/<profile>`), with a one-line why-comment above it.
   Prefer an existing abstraction (`include <abstractions/dotfiles/viewer-read>`).
3. Compile check without root:
   ```bash
   configs/base/apparmor/apparmor.test.nu
   ```
   Exit 0 is clean; the "Failed to create cache" warnings are expected.
4. Load it on this machine: `dot system` (the module's `system` verb installs and reloads, then fails if any profile
   is not in its expected mode). For a quick loop on a `local/` rule the user can run
   `sudo install -m644 configs/base/apparmor/local/<p> /etc/apparmor.d/local/<p> && sudo apparmor_parser -r /etc/apparmor.d/<p>`
   (`<p>.apparmor.d` where apparmor.d replaced a stock profile); `dot system` must still be run so it is reproducible.
5. Retry the app and recheck the log. `dot test lint` runs the same test.
