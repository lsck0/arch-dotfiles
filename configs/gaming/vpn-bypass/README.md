# Games bypass the VPN

Traffic of the `vpn-bypass` group leaves on the physical link while ProtonVPN is up; everything else stays in the
tunnel.

- `vpn-bypass` is a system group of its own with no members: `newgrp` would hand a member the bypass unasked, and the
  shared `games` gid would hand it to every setgid game (nethack).
- `steam-launch.nu` runs Steam (and its games), while `proton0` is up, as group `vpn-bypass` through `games-run`,
  which pkexec authorizes under its own action `dev.lsck0.vpn-bypass.games-run` (`dev.lsck0.vpn-bypass.policy`,
  `auth_admin_keep`): one key touch, kept a few minutes for `games-run` only, never for another pkexec.
- `games-bypass.nft` marks sockets of group `vpn-bypass` with `0x6761` and masquerades them off the tunnel;
  `games-route.nu` (NM dispatcher) points table 100 at the physical gateway with `ip rule fwmark 0x6761 lookup 100`
  and mirrors main's connected routes (LAN, virbr0, docker) and the homelab's table 178 into it, the lab nets
  unreachable behind them as in main; `fw-egress.nft` lets the mark out.

Every failure falls back to the game using the VPN, never to a leak. The fail-closed tools of
`base/protonvpn-netns` are unaffected.
