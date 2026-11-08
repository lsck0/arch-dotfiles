---
name: l-homelab
description: Using Luca's homelab from this machine: its services and hostnames (tasks, cal, grafana, ntfy, mirror, nas, auth, ...), how they are reached (lab DNS, LAN or wireguard), which dotfiles secrets hold their tokens, lab.json, and how homelab changes are requested. Load before an agent calls a *.lsck0.dev service, wires a desktop tool to the homelab, debugs a homelab-backed feature (task sync, calendar, bar's homelab widget, the mirror, the NAS share), or wants anything changed on the homelab.
---

# l-homelab

The homelab is its own repo, `~/projects/homelab`, with its own agent session. This machine only consumes it; every
change goes through that repo and session, since a hand change on a guest is lost or drifts.

## Services

`https://<name>.lsck0.dev`, one wildcard certificate. `*`: behind Authelia SSO. Every route with its host and zone
(internal or external): lab.json's `routes`.

| reach | name | what |
|---|---|---|
| internal | `tasks` | taskchampion sync (own client id/secret) |
| internal | `cal` | calendar feeds and ICS upload (own token) |
| internal | `terminal` | TRMNL feeds |
| internal | `grafana`*, `homelab`*, `start`*, `search` | metrics; admin dashboard; dashboard; searxng |
| internal | `nas`*, `backup`*, `sync`* | filebrowser; kopia; syncthing |
| internal | `auth`, `lldap`* | Authelia and OIDC; users |
| internal | `git`, `wiki`, `sccache`, `hs`, `hs-ui` | forgejo; wiki; build cache; headscale and its UI |
| internal | `registry` (basic auth), `registry-ui`*, `archbuild`* | registry; its UI; mirror build |
| infra | `proxmox`* | hypervisor (lab.json `proxmox`, not a route) |
| external | `ntfy`, `mirror`, `paste`, `share` | push; `[lsck0]` repo and iso; privatebin; files |
| external | `ts`, `*.mc` | teamspeak; minecraft |
| external | `hello`, `math`, `nyangine`; `deploy` | swarm apps (lab.json `app`); the dev guest's deploy endpoint |

`search` takes a login only from outside the house and wireguard. The media guest (jellyfin and the rest) is parked:
treat it as absent.

## Reaching it

- Names resolve through the lab DNS. Bootstrap resolver `192.168.178.29`; `base/networkmanager` routes the lab domain
  to it (options `homelab_dns`, `homelab_domain`, defaulting to `platforms/homelab.nu`).
- Internal routes answer only on the LAN and over wireguard (`toggle-vpn`, `wg0`); external ones anywhere.
- SMB share `//10.100.0.100/homelab`, credentials `samba-homelab` (`core/nas`).
- After a service moves: `sudo resolvectl flush-caches` (ask Luca).

## Credentials

In `configs/secrets/keys/` (`l-dotfiles-secrets-access`), names only: `taskwarrior-client-id`,
`taskwarrior-encryption-secret` (`programming/task`), `calendar.env` with `CALENDAR_FEED`, `CALENDAR_UPLOAD`
(`task-calendar`), `ntfy-desktop-token` (`core/ntfy`), `samba-homelab` (`core/nas`). Users and groups in lldap
(`admins`, `app-<route>`).

## lab.json

`~/projects/homelab/src/generated/lab.json`, schema 1 (documented in `src/modules/lab-export.nix`): guests and routes,
read by the bar's `homelab-status.nu` (guests found by `roles`, never by name) and the ntfy notifier. Use only what
schema 1 provides. `dot internal gen` renders its addresses, subnets and mirrors into the committed
`platforms/homelab.nu`, the dotfiles' one source for them; `dot test lint` fails while it is stale.

## Changing the homelab

- Message the session named `homelab-*` (list agents) with the exact need and what depends on it here.
- Never from here: `./sync.nu`, editing or decrypting `src` secrets, ssh into a guest to change it, Proxmox. Reading
  lab.json, DNS and public endpoints is fine.
- How the lab works: `~/projects/homelab/README.md`, `FEATURES.md`, `src/instances/preconfigured/**/skill.md`.

## Debugging

A guest (internal `10.100.0.0/24`, dmz `10.200.0.0/24`) that times out on TCP but answers ping is not down: the
router opens flows only to specific source IPs (`src/modules/flows.nix`, `workstation`/`notebook`). Compare:

```bash
ip -4 addr show <iface>
grep -A1 '"workstation"\|"notebook"' ~/projects/homelab/src/generated/site.json
```

A mismatched lease: `nmcli connection down/up <profile>`, or fix the router's reservation; never the dotfiles.

The NAS share hangs the same way: only `mnt-homelab.mount`'s `TimeoutSec` (`core/nas`) bounds it, not
`soft`/`echo_interval`. The automount has no negative cache, so every stat through `/mnt/homelab` (or `~/nas`) hangs
again until the route is fixed.

## Gotchas

- `task-sync.service` skips when `tasks` is unreachable. A 500 is the lab's problem: report it.
- `cal` only serves the feeds Luca uploads.
- Use hostnames in dotfiles code, never vmids or guest addresses.
