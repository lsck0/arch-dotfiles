# TODO

Open items from the luca-notebook review on 2026-11-05: each needs the PC, root, a foreign network, or a decision.

## Root or Luca's YubiKey

- [ ] Find out why the install chain left `pacman-filesdb-refresh.timer` disabled. `base/pacman` declares it, gated on
  the unit file through its `inputs`, but the system layer did not run again once `pacman-contrib` brought the file. A
  manual `dot apply --system` fixed it on 2026-11-05; a fresh install should not need one.
- [ ] Enroll the TPM2 token. `rd.luks.options` asks for one and every boot logs "No valid TPM2 token data found".
  `dot status` names the `systemd-cryptenroll` command.
- [ ] Do the recovery drill (RECOVERY.md "Test it"), then run `dot secrets audit drilled`.

## Needs the PC

- [ ] Discord no longer shows "Streaming" while live on Twitch. Check these on the PC:
  - Discord, Connections, Twitch: "Display on profile" is on.
  - Activity Privacy: "Share your detected activities" is on.
  - Then turn off Incognito's `blockProcessScanning` and DoNotTrack's process monitoring, one at a time. Both stop the
    client's process detection (OBS included), and Incognito was added on 2026-10-14. If one of them is the cause,
    pin that setting to false in `configs/socials/discord/mod.nu`, as `blockReadReceipts` is.
- [ ] OBS alert sounds: `configs/desktop/pipewire/app-loopback.lua` now leaves `obs-browser-page` streams alone. The
  "... For Me" browser sources play there and were muted with every other loopback while HEAR was on. Check on the PC
  that a test alert plays both locally and on the stream. The other two, "Twitch Alerts" and "Sound Alerts", go
  through OBS tracks 1, 3 and 4 (`reroute_audio`).
- [ ] Pull the new ollama pins. `qwen3-embedding:8b` (4.7 GB) and `qwen3-coder:30b` (18.6 GB) are added to
  `ollama-ensure-models.nu`. The new stamp pulls them on the next `dot apply llm/ollama` on the PC.
- [ ] Local image and 3D models need a GPU module. Decide on one, for example a `llm/comfyui` module:
  - ComfyUI in a uv venv with a pinned commit, a socket-activated unit like `llm/vllm`.
  - Images: FLUX.1-schnell (Apache-2.0), or SDXL.
  - 3D: Hunyuan3D-2 or TRELLIS through their ComfyUI nodes.
  - Every model pinned by hub revision.
  The notebook has no GPU to test this on.

## Needs a foreign network

- [ ] After `dot apply --system` on a trusted network (luca-phone), check the home/trusted split:
  - `/run/trusted-network` lists `wlp2s0` and `/run/home-network` is gone.
  - `resolvectl status wlp2s0` shows the hotspot's DNS, not 192.168.178.29.
  - `nmcli general` shows `full`.
  - `nft list set inet fw trusted_links` holds `wlp2s0`.
  - Back home, both files list the link again.

- [ ] eduroam: the bar's wifi panel now asks for an identity on WPA-EAP networks. It makes a PEAP/MSCHAPv2 profile that
  checks the RADIUS certificate against the system CAs and `domain-suffix-match=<realm>`. Some universities use TTLS/PAP
  or a RADIUS name outside the realm. If the connection fails, run
  `journalctl -u NetworkManager -u wpa_supplicant | grep -i eap`, then fix the profile with values from the university's
  eduroam CAT (cat.eduroam.org) page.
- [ ] wake-pc away from home: the router is now asked at `wake_router_tunnel` (10.0.0.1) over wg0. Check that the
  router's sshd answers on its wg address. If the foreign LAN is also 192.168.178.0/24 (any FritzBox), the PC's LAN
  address is shadowed, and wake-pc stops after the magic packet. The PC would need its own wg address up at boot
  (10.0.0.5, `wg0.pc.conf`) to be reachable then.

## Homelab (via the homelab session)

- [ ] SearXNG at search.lsck0.dev: results are poor and the image tab is missing or empty. Review its engines and
  categories in the homelab repo. The browsers already default to it on homelab machines; qutebrowser on the notebook
  fell back to DuckDuckGo because of an options bug, which is fixed now.

## Decision

- [ ] Encrypting only /home instead of the whole disk. On this i7-8650U, AES-XTS runs at about 2.3 GB/s
  (`cryptsetup benchmark`). That is faster than the NVMe, and the header already carries allow-discards and the
  no-workqueue flags. Full-disk encryption is not the likely cost. With only /home encrypted, /etc, the NM wifi keys,
  the ssh host keys and the logs would be plaintext, and it needs a repartition (a reinstall). A cheaper lever first:
  btrfs `compress=zstd:1` instead of `zstd:3` on the notebook, which costs CPU on every write.
- [ ] Syncthing logs "Unexpected folder ID borg-luca-notebook" from device FEA6R7Y. Either accept that folder through
  `core/syncthing` or stop sharing it from the other device.
