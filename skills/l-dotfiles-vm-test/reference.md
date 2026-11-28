# vm-test reference

Constants are at the top of `scripts/lib/vm.nu`.

## VM

- `qemu:///session`, Secure Boot in Setup Mode (`OVMF_CODE.secboot.4m.fd` with a fresh `OVMF_VARS.4m.fd` copy), no
  TPM, 200 GiB. It boots the iso plus a cd labelled `LSCK0` with `lsck0.nuon` (`unattended: true`), the snapshot
  bundle and its lfs objects. The stub applies the bundle and execs its own stub, so a published iso runs the current
  installer.
- qemu, pasta, passt, socat and the heavy host steps run at nice 19 and idle io class.

## Network

- The nic is a qemu stream netdev to passt, inside a pasta namespace of the user's own (`network.log`); a scenario's
  blocked cidrs are unreachable routes there. Launched through `pkexec /usr/local/bin/vm-net` (base/portmaster,
  unprompted via polkit, group vmnet so portmaster passes the guest's DoT to quad9); without it (not installed, pkexec
  refused over ssh) the plain launch runs and warns, and portmaster may then block the guest's DNS.
- The guest sees `10.0.2.15/24`, gateway `10.0.2.2`, dns `10.0.2.3` or the scenario's. passt relays dns to the
  platform's `homelab_dns` (split horizon as at home), else 9.9.9.9, never the host's 127.0.0.53 stub.
- Reports: a socat server (`scripts/lib/vm/serve.sh`) on the first free host port from 8765, reached by the guest as
  `10.0.2.2:8765` through pasta `-T`, via the answers' `report` url; the chain's end also writes to the virtio channel
  `lsck0.report`, which no guest firewall stands in front of.

## Beacons

- The iso install beacons `bootstrap-ok` (http and channel) and powers off. On failure it uploads
  `/tmp/lsck0-install.log` to `host/upload/bootstrap.log` and beacons `bootstrap-fail`.
- Stages beacon `install-ok|failed` and `config-ok|failed` (`stage.nu`, `/var/lib/dotfiles-stage/report`).
- The chain's end runs `scripts/lib/stage-report.nu` as root: probes from `scripts/lib/invariants.txt`,
  `dot status --json`, `dot internal backup --roundtrip`, stage log, journals, network and nft state, `/etc/issue.d`,
  `FAILURES.*`, `*.log`. It uploads `logs.tgz` to `host/upload/`, beacons `chain-done` (`chain-fail` on a failed
  report or a stopped chain) and reboots to the passphrase prompt.

## Pass criteria

Every invariant row at its value (`any` rows only where the scenario's `expect` names them), `backup_roundtrip=ok`,
`sshd_installed=yes`, and `mirror_reachable=yes` or a banner naming a `dot` command (`issue_escape=yes`). Then either:

- each stage as the scenario's `stages` say (`ok` by default), no `FAILURES.*` line but its `failures_allowed` ones,
  and no error in `status.json` unless every failure line was allowed; or
- a chain stopped before config (`chain_stopped=yes`, probed after the disarm, so `stage_armed`, `sudo_passwordless`,
  `keyfile_present` and `luks_keyslots` keep their values) with its banner and the rows of `scenarios.nuon`'s
  `stopped` at theirs.

`dot status` FAIL checks print as notes.
