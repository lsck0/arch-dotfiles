# Games bypass the VPN

ProtonVPN auto-raises on an untrusted network (`configs/base/protonvpn`). While `proton0` is up every connection goes
through the tunnel, which slows game frontends and risks an anticheat flag on the shared exit IP. A game reveals who is
playing regardless, so it gains no privacy from the tunnel. This routes the games group's traffic out the real physical
link instead, and only that traffic.

## Mechanism

- `games` group: every admin is a member (`group-admins`). `configs/gaming/steam/steam-launch.nu` switches Steam
  (and so every game it starts) into it with `sudo -g games`, passwordless through the `sudoers` drop-in.
- `games-bypass.nft` (table `inet games_bypass`): a `route`-hooked output chain marks every socket whose group is
  `games` with `game_mark` (0x6761) and triggers a reroute. `games-bypass.service` loads it and fills the gid.
- `games-route.nu` (NM dispatcher `85-games-route`): keeps routing table 100 pointed at the current physical gateway
  and an `ip rule fwmark 0x6761 lookup 100` at priority 9000, above a full-tunnel VPN's own rules.
- `configs/base/nftables/fw-egress.nft`: the kill switch lets `game_mark` out of the otherwise closed physical link.

A marked packet is rerouted into table 100, leaves on the physical gateway with the real source IP (replies pass loose
`rp_filter`), and is accepted by the kill switch. Nothing else is ever marked.

## Fail safe

Every failure degrades to "the game uses the VPN", never to a leak and never to broken connectivity:

- Not in the group, or the sudoers is missing: `steam-launch.nu` launches Steam plain, its sockets are unmarked, they
  take the main table through `proton0`.
- `games_bypass` not loaded: no mark, same result.
- Table 100 or the `ip rule` missing: a marked packet finds no fwmark rule and falls through to the main table and the
  tunnel; the kill switch still permits it (it leaves on `proton0`).
- At home / trusted (`proton0` down): table 100's gateway is the normal default, so the bypass is a no-op.

The kill switch stays closed for everything that is not `game_mark`, and the fail-closed privacy tools
(`configs/base/protonvpn-netns`: yt-dlp, ani-cli, mpv-stream) are untouched.
