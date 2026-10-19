# Bugs

What is still open from my own list after the review passes of 2026-10-18 and 2026-10-19. Everything else on it is
fixed in the repo; what is applied but waits for a reboot is under "Needs a reboot".

## Open

Upstream, nothing to fix here:

- nvim `grid.c:672: grid_put_linebuf: Assertion '0 <= row && row < grid->rows'`: neovim's ui2 with
  `laststatus = 3`. Workaround if it keeps crashing: drop the `vim._core.ui2` line in `init.lua`.
- Median XL crashes inside its own `D2Sigma.dll` (`ACCESS_VIOLATION`, fault address `100619AB`), about 40 s into a
  game on 2026-10-19; the launcher and wine side start it fine. The dump is
  `~/.d2launcher/bin/diablo2/Logs/D2Debug-261019.txt`, the report goes to the Median XL forum or Discord.

Needs me:

- Packages declared but not installed (`dot status`). `k6-bin`, `lyx` and `raddebugger` are not on the `[lsck0]`
  mirror yet: build them there. `namcap`, `speech-dispatcher`, `netkit-bsd-finger` and `wmctrl` are available now.
  Then `dot apply --packages`.
- `configs/base/keyboard/sofle_choc.uf2` has the new keymap. It is a git LFS object that is not committed or pushed
  yet; `dot sync` does both. Flash it to both halves.
- Rotate the Twitch stream key as a precaution: the OBS profile holds it in plain text, and agents had read access
  to it during the review. Reset it in the Twitch dashboard (Settings, Stream), paste the new one in OBS (Settings,
  Stream); the `backup` verb of `creating/obs` copies it to `secrets/obs-service.json` on the next `dot sync`.
- Remove the temporary passwordless sudo drop-in made for the review: every file in `/etc/sudoers.d/` except
  `10-wheel`, `20-protonvpn-netns` and `25-games-bypass` (the stage chain's `zz-dotfiles-stage` is gone once the
  install finished). `sudo -n true` fails again once it is gone.
- The LUKS header backup is missing: run `configs/base/boot/luks/header-backup.nu` with secrets unlocked.
- Wake-on-LAN from poweroff: the NIC side is set (`ethernet.wake-on-lan`), the BIOS also needs ErP disabled.
- Spotify stays quiet until wireplumber rereads its config: `systemctl --user restart wireplumber` once.
- Discord lags with the real camera on. Only the virtual camera got a fix (720p output in `creating/obs`).
- Showcase screenshots are not retaken.

## Needs a reboot

Applied on 2026-10-18; these only take effect at the next boot:

- plymouth `loglevel=3` and quiet status on the kernel cmdline, ly on tty1 with no getty in between.
- bluetooth `AutoEnable=false`, wake-on-lan on the home ethernet.
- the 15 s user stop timeout behind `mod+shift+e` (read at the next login).

# Known bugs

Open findings from the full AI code review of 2026-10-15. The 52 bugs that were fixed in that pass are not listed
here; this file is the backlog of what was found and deliberately left alone, so it is not rediscovered every time.

Nothing here is dangerous today by the standard in `AGENTS.md`: no auth bypass, no data loss, no broken boot or
desktop. Most are latent, cosmetic, or a deliberate tradeoff.

## Deliberate tradeoffs, confirm before changing

- `configs/base/systemd/mod.nu:39` masks `NetworkManager-wait-online.service`, which makes `network-online.target`
  fire immediately. Six units order themselves after that target and now start before the network is up. Removing
  the mask costs boot time on every machine; the blast radius is why it was left.
- `configs/base/hardening/sysctl-hardening.conf:18` sets `fs.suid_dumpable = 0` while the coredump module expects
  dumps. This reads as intentional hardening rather than a mistake.
- Firewall narrowing in `configs/base/nftables`: the tunnel fwmark rule accepts both protocols where only UDP is
  needed, and the inbound chain does not enumerate MLD types. Both are judgement calls about how tight to go.
- `configs/base/yubikey/mod.nu:23` installs an `id_ed25519_sk` stub from only the first matching key, so a second
  resident key is never wired up.

## Cosmetic and low impact

A set of low-severity quickshell/QML findings (mostly unlikely races that heal themselves on the next event, and
binding nits) was reviewed in the same pass and dropped without individual records.
