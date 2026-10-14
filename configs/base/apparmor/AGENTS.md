# base/apparmor

Extends the root `AGENTS.md` and the `configs/base/AGENTS.md`. AppArmor confinement: which apps are confined and
how strictly.

## Layout

- `profiles.conf`: the authoritative mode table. Column one is apparmor.d's own profiles (loaded through include.d by
  `aa-install`), the rest are this module's own. `<mode>,<flag>` adds profile flags (e.g. `telegram-desktop enforce,mediate_deleted`).
- `profiles/`: this module's own profiles, for programs apparmor.d does not cover (feh, nsxiv, sioyek, bookokrat,
  zapzap, zotero, obsidian, the archive/image tools, `handbrake`, `blender-mcp`, `obs-mcp`, `localsend-app`). Each
  carries its mode in its header.
- `local/`: drop-ins layered onto apparmor.d's profiles (firefox, chromium, qutebrowser, discord, telegram, mpv,
  thunderbird, zathura, libreoffice, spotify, signal, ffmpeg, ffprobe). This is where a confined app's child-exec and
  file access are narrowed.
- `abstractions/`: shared rule fragments (`deny-sensitive-home`, `child-open`, `xdg-open`, `synctex-edit`, `qtwebengine`,
  `viewer-read`, `gpg-client`, ...).
- `modes`, `sysctl-apparmor.conf`, `aa.nu` (the `aa` command), `mod.nu`, `apparmor.test.nu`.

## Policy

- Everything that opens other people's content stays `enforce`. `apparmor.test.nu` keeps the enforce list honest and
  fails if one drops to complain.
- A confined program may only exec into a loaded profile. The openers (`child-open`, `child-open-any`,
  `child-open-browsers`, `child-open-strict`) are enforced too; targets that would confine a general tool everywhere
  (dolphin for "show in folder") stay unloaded so the exec fails instead. gpg (thunderbird, libreoffice) and yt-dlp
  (mpv) run in their own `local/` child.
- `aa complain <profile>` backs one profile off on a single machine; `aa off` unloads it. Never edit the baseline to
  relax policy. `aa enforce <profile>` re-confines. The `aa` tool layers choices into `manual.conf` drop-ins that
  config runs never touch, reboot-safe.

## Testing

- `./apparmor.test.nu`: checks `profiles.conf` policy and compiles every own profile and `local/` drop-in. The
  "Failed to create cache" warnings are expected without root. Part of `dot test lint`.

See the `l-dotfiles-apparmor-profile` skill for writing or adjusting a profile and reading denials.
