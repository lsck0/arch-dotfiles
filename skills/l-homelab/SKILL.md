---
name: l-homelab
description: Using Luca's homelab from this machine: its services and hostnames (tasks, cal, grafana, ntfy, mirror, nas, auth, ...), how they are reached (lab DNS, LAN or wireguard), which dotfiles secrets hold their tokens, lab.json, and how homelab changes are requested. Load before an agent calls a *.lsck0.dev service, wires a desktop tool to the homelab, debugs a homelab-backed feature (task sync, calendar, bar's homelab widget, the mirror, the NAS share), or wants anything changed on the homelab.
---

# l-homelab

The homelab is its own repo, `~/projects/homelab`, with its own agent session. This machine only consumes it. Every
homelab change goes through that repo and that session, never ad hoc from here, for the same reason machine changes
go through the dotfiles: the lab is rebuilt from its repo, so a hand change on a guest is lost or, worse, drifts.

## Services

All under `https://<name>.lsck0.dev`, one wildcard certificate. `*` marks the ones behind Authelia SSO.

| Reach | Name | What |
|---|---|---|
| internal | `tasks` | taskchampion sync server (own client id/secret) |
| internal | `cal` | calendar feeds and the ICS upload endpoint (own token) |
| internal | `terminal` | TRMNL panel feeds (calendar day/week JSON) |
| internal | `grafana`*, `homelab`*, `start`* | metrics; admins' dashboard; everyone's dashboard |
| internal | `nas`*, `backup`*, `sync`* | filebrowser; kopia UI; syncthing UI |
| internal | `auth`, `lldap`* | Authelia portal and OIDC; user directory |
| internal | `registry` (basic auth), `registry-ui`*, `traefik`*, `proxmox`*, `archbuild`* | container registry; ingress; hypervisor; mirror build |
| public | `ntfy`, `mirror`, `search`, `paste`, `share`, `apps` | push notifications; the `[lsck0]` pacman repo and install ISO; searxng; privatebin; file share; demo apps |

The media guest (jellyfin, `*arr`, torrent) is parked: treat it as absent.

## Reaching it

- Names resolve through the lab DNS on the router. The one address that is not a name is the bootstrap resolver
  `192.168.178.29`; `base/networkmanager` routes the lab domain to it (options `homelab_dns`, `homelab_domain`).
- Internal routes answer only on the house LAN and over the owner's wireguard (`toggle-vpn`, interface `wg0`).
  Public routes go through the edge and work anywhere.
- The SMB share `//10.100.0.104/homelab` has no name yet; its credentials are the dotfiles secret `samba-homelab`
  (`core/nas` mounts it).
- After the lab moves a service, a stale DNS cache here points at the old address: `sudo resolvectl flush-caches`
  (root; ask Luca).

## Credentials on this side

Dotfiles secrets (git-crypt, `configs/secrets/keys/`, skill `l-dotfiles-secrets-access`), names only:
`taskwarrior-client-id` and `taskwarrior-encryption-secret` (`programming/task`), `calendar.env` with
`CALENDAR_FEED` and `CALENDAR_UPLOAD` (`task-calendar`), `ntfy-desktop-token` (`core/ntfy`), `samba-homelab`
(`core/nas`). Users and groups live in lldap (`admins`, `app-<route>`); Authelia gates the `*` routes in a browser.

## lab.json

`~/projects/homelab/src/generated/lab.json`, schema 1, documented at the top of `src/modules/lab-export.nix`. It
lists guests and routes; the bar's homelab widget (`homelab-status.nu`) and the ntfy notifier read it. Join by what
schema 1 provides; do not assume names or fields beyond it.

## Changing the homelab

- Message the homelab session: list agents, the one named `homelab-*` (sessions get renamed; match the repo name).
  State the exact need and what on this machine depends on it.
- From this machine never run `./sync.nu`, never edit or decrypt `src` secrets, never ssh into a guest to change it,
  never touch Proxmox. Reading lab.json, DNS and public endpoints is fine.
- Guests are reached as `root@<guest ip>` through the router as bastion, with host keys pinned in
  `src/generated/known_hosts` and an ssh_config that `sync.nu` writes. That is the homelab session's tool, not ours.
- For how the lab itself works: `~/projects/homelab/README.md`, `FEATURES.md`, and the per-guest `skill.md` under
  `src/instances/preconfigured/**`.

## Debugging

When a mount, ssh or any named service on a homelab guest (internal `10.100.0.0/24`, dmz `10.200.0.0/24`) times out
on TCP while ICMP to the same address succeeds, the guest isn't down: the router's firewall only opens that flow to specific source IPs
(`~/projects/homelab/src/modules/flows.nix`, the named `workstation`/`notebook` sources), not the whole subnet.
Compare this machine's current DHCP lease against the IP the firewall trusts:

```bash
ip -4 addr show <iface>                                                         # current lease
grep -A1 '"workstation"\|"notebook"' ~/projects/homelab/src/generated/site.json # the IP the firewall trusts
```

A mismatch (the router gave a different lease than its own reservation) silently locks out every named TCP flow
while ping still answers; fix is a DHCP renew (`nmcli connection down/up <profile>`) or the router's reservation
itself, never the dotfiles.

A `.mount` unit's own `TimeoutSec` is the only thing that bounds the hang in this failure mode: against a host
that drops packets instead of rejecting them, the kernel's TCP connect takes longer than any application-level
timeout can interrupt, so a short `TimeoutSec` (not `soft`/`echo_interval`) is what caps the wait. autofs has no
negative cache, so every stat through the mountpoint (or a symlink into it, e.g. `~/nas`) re-triggers the same hang
until the route to the host is fixed.

## Gotchas

- `task-sync.service` skips (not fails) when `tasks` does not answer, so being away from home is quiet. A 500 from
  the server is the lab's problem (storage permissions after a move, for one): report it to the homelab session.
- Uploading tasks into the terminal calendar was dropped on the lab side; `cal` only serves the feeds Luca uploads.
- Use hostnames, never vmids or guest addresses, in dotfiles code: the lab restructures and renumbers guests.
