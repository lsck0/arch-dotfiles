---
name: l-dotfiles-apparmor-profile
description: "Writing or adjusting AppArmor profiles and local/ drop-ins in configs/base/apparmor, reading DENIED lines, apparmor.test.nu, the aa command and the enforce policy. Load when an app is blocked by AppArmor, a profile transition is not found, or a new app needs confinement. Reproducing the denial in a GUI app: l-dotfiles-gui-testing."
---

# apparmor-profile

Built on apparmor.d (`aa-install`). In `configs/base/apparmor/`:

- `config/profiles.conf`: the mode of every deployed profile, `<name> <mode>[,flags]`. `,flags` only for apparmor.d's;
  an own profile keeps its flags in its `profile` line and `mod.nu` writes the mode into it.
- `config/profiles/<name>`: own profiles, installed as `/etc/apparmor.d/<name>.dotfiles`. First line
  `# managed by arch-dotfiles/apparmor`, then `profile <name> <attachment> flags=(...)`.
- `OVERRIDES` in `mod.nu`: apparmor.d profiles with a brace attachment (firefox, thunderbird, libreoffice, browserpass)
  regenerated as own profiles from the installed one, only the attachment swapped; apply and test fail once
  apparmor.d stops shipping one. A `profile transition not found` denial into an apparmor.d program is this case.
- `config/local/<name>`: extra rules for an apparmor.d profile (`/etc/apparmor.d/local/<name>`); the name must be in
  `config/profiles.conf`.
- `config/abstractions/<name>`: installed as `abstractions/dotfiles/<name>`.

## Rules

- Everything that opens other people's content (browsers, mail, chat, media, documents, images, archives,
  `child-open*`) stays `enforce`; `apparmor.test.nu` fails otherwise.
- Backing a profile off is Luca's, on one machine, never in the baseline: `aa complain|off|enforce <profile>` (sudo;
  writes `/etc/apparmor/{flags,include}.d/manual.conf`, survives runs). `aa` (sudo) shows loaded modes and his
  choices; `aa list [filter]` lists apparmor.d's names without root.
- A rule names the checkout `@{DOTFILES}`, never `projects/arch-dotfiles` (the test fails).
- A confined program may only exec into a loaded profile.

## Fix a denial

1. Reproduce it (a GUI app the way `l-dotfiles-gui-testing` allows: ask Luca first), then read
   `journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail`: `profile=`, `operation=`, `name=`, `requested_mask=`.
2. Add the narrowest rule to `config/local/<profile>` or `config/profiles/<profile>`; prefer an abstraction
   (`include <abstractions/dotfiles/viewer-read>`).
3. `configs/base/apparmor/apparmor.test.nu` (no root) until it exits 0.
4. `DOT_SYSTEM=skip dot apply` (system part pending, exit 3), then ask Luca for `dot apply --system`: it installs,
   reloads and fails when a profile is not in its mode. Does nothing on WSL, installs no profiles without apparmor.d.
5. Retry and recheck the log; back to 2 while denials remain.

Quick loop for Luca (sudo), followed by `dot apply --system` all the same:

```bash
sudo install -m644 configs/base/apparmor/config/local/<p> /etc/apparmor.d/local/<p>
sudo apparmor_parser -r /etc/apparmor.d/<file>
```

`<file>` is `<p>.dotfiles` when it exists (own profile or `OVERRIDES` entry), else `<p>.apparmor.d` when it exists,
else `<p>`. Never reload the bare `<p>` of an own profile: it is the stock unconfined stub and replaces the enforced
one.
