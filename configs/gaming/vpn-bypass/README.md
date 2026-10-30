# Games bypass the VPN

Traffic of the `games` group leaves on the physical link while ProtonVPN is up; everything else stays in the tunnel.

- `steam-launch.nu` runs Steam (and its games) as group `games` (`sudo -g games`, passwordless via the sudoers drop-in).
- `games-bypass.nft` marks sockets of group `games` with `0x6761` and masquerades them off the tunnel;
  `games-route.nu` (NM dispatcher) points table 100 at the physical gateway with `ip rule fwmark 0x6761 lookup 100`
  and mirrors main's connected routes (LAN, virbr0, docker) and the homelab's table 178 into it, the lab nets
  unreachable behind them as in main; `fw-egress.nft` lets the mark out.

Every failure falls back to the game using the VPN, never to a leak. The fail-closed tools of
`base/protonvpn-netns` are unaffected.
