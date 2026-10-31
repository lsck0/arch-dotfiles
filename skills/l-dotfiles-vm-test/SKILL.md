---
name: l-dotfiles-vm-test
description: "The end-to-end test, dot test run: the lsck0 iso with an answer file in a libvirt VM through the whole unattended chain, the chain's own report, screenshot and teardown. Takes hours. Load before testing a fresh install or the install stages."
---

# vm-test

`dot test run` runs as the user, no sudo anywhere: a `qemu:///session` VM (Secure Boot in Setup Mode from
`OVMF_CODE.secboot.4m.fd` and a fresh `OVMF_VARS.4m.fd` copy, no TPM, 200 GiB) from the lsck0 iso plus a cd labelled
`LSCK0` with the answers (`lsck0.nuon`, `unattended: true`), the snapshot bundle and its lfs objects. Disk, NVRAM,
answers, serial log and the report channel all live in `$XDG_CACHE_HOME/vm-test/<name>/`. Its nic is a qemu stream
netdev to passt, which runs inside a pasta namespace of the user's own (`network.log`): a scenario's blocked cidrs are
unreachable routes there. The guest sees `10.0.2.15/24`, gateway `10.0.2.2` (MAC `9a:55:9a:55:9a:55`), dns
`10.0.2.3` (passt relays it to the home router, `base/networkmanager`'s `homelab_dns`, so split horizon works as at
home; passt skips the host's 127.0.0.53 stub) or the scenario's. It reports to a socat server on the host
(`scripts/lib/vm/serve.sh`, the first free port from 8765, `10.0.2.2:8765` from the guest through pasta `-T`) via the
answers' `report` url, and the chain's end also over the virtio channel `lsck0.report` (`report.log`), which no guest
firewall stands in front of. qemu, pasta, passt, socat and the heavy host steps get nice 19 and idle io. socat and
pasta keep pidfiles in the cache dir; `dot test destroy` and the next run stop them by pidfile and command line, so a
ctrl+c leaves them only until then. Up to 12 h a run.

## Before

- `dot test lint` (`run` runs it first).
- `kvm` group, `virt-install`, `virsh`, `passt`, `pasta`, `socat`, `xorriso`, `curl`; `magick` for `shot`.
- The iso: the published one, fetched to `$XDG_CACHE_HOME/vm-test/` and checked against `.sha256`; `--iso PATH` a
  local build.
- Tests the working tree (untracked included) as a bundle over `origin/master`; `--master` tests GitHub master. The
  stub applies the bundle and execs its own stub, so a published iso runs the current installer.

## Run

```bash
dot test run                              # platforms/vm.nuon, login luca (--user <login>), profile luca
dot test run --platform luca-notebook
dot test run --profile custom
dot test run --platform server
dot test run --name other-vm              # beside the default archlinux-test
dot test run --iso "${XDG_CACHE_HOME:-$HOME/.cache}"/dotfiles-iso/out/archlinux-lsck0-latest-x86_64.iso
```

Run it in the background; it prints each beacon and exits 1 with the problems.

## Scenarios

`--scenario` (default `home`) takes a comma list from `scripts/lib/vm/scenarios.nuon`, layered over `home`; two
that disagree (`home,off-home`) are refused. `all` runs each scenario and preset alone, one fresh VM each, in a row.
`--dry-run` prints each run's answers, pasta and virt-install lines and snapshot edits, booting nothing.

| scenario | condition |
|---|---|
| `home` | `home_network: true`, so the install records passt's gateway MAC; wants `home_network=yes` |
| `off-home` | `home_network: false`; the host's lan, the lab (`homelab_subnets`) and IPv6 (passt `-4`) out of reach, dns 9.9.9.9 |
| `secrets-locked` | profile `luca`, `--redirdev none`, so no YubiKey reaches the guest; wants the secrets banner |
| `public-mirror` | the lab (`homelab_subnets` of the run's and the host's platform) unreachable, guest dns 9.9.9.9 |
| `pkg-fail` | `extra_packages: [lsck0-vm-test-unresolvable]` in the platform file; wants install `failed`, config `ok`, `planted_dropped=yes` |
| `no-tor` | `base/tor` declares `lsck0-vm-test-no-tor` in place of `tor`; as pkg-fail, plus `tor_installed=no` |
| `notebook-2026-10-30` | preset: off-home, secrets-locked, public-mirror on `luca-notebook` |

```bash
dot test run --scenario off-home,public-mirror
dot test run --scenario notebook-2026-10-30
dot test run --scenario all --dry-run
```

Snapshot edits need the snapshot, so `pkg-fail` and `no-tor` refuse `--master`. A `replace` whose pattern no longer
matches stops the run (and `vm.test.nu` in lint), so a refactor cannot void a scenario.

## Reports

- Install beacons `bootstrap-ok` (http and channel) and powers the VM off when done; a power-off without it is a crash
  (see `serial.log`), as is a guest that goes down mid-chain with no verdict. On failure the stub uploads `/tmp/lsck0-install.log` to
  `$XDG_CACHE_HOME/vm-test/<name>/host/upload/bootstrap.log` and beacons `bootstrap-fail`.
- Stages beacon `install-ok|failed`, `config-ok|failed` (`stage.nu`, `/var/lib/dotfiles-stage/report`).
- The chain's end runs `scripts/lib/stage-report.nu` as root: probes in `scripts/lib/invariants.txt`,
  `dot status --json` (`status.json`), `dot internal backup --roundtrip`, stage log, journals, network and nft state,
  `/etc/issue.d`, `FAILURES.*`, `*.log`; uploads `logs.tgz` and writes it to the channel, beacons `chain-done`,
  reboots (waits at the passphrase; not unlocked).
- `$XDG_CACHE_HOME/vm-test/<name>/logs/<scenario>`: the report. Pass is `dot test: <scenario>: chain succeeded`,
  wanting every invariant row at its value (`any` rows only where the scenario's `expect` names them),
  `backup_roundtrip=ok`, `sshd_installed=yes`, a mirror reachable (`mirror_reachable=yes`) or a banner naming a `dot`
  command (`issue_escape=yes`), and either each stage as the scenario's `stages` say (`ok` by default), no `FAILURES.*`
  line but its `failures_allowed` ones (notes) and no error in `status.json` unless every failure line was allowed, or
  a chain stopped before config (`chain_stopped=yes`: `--stopped` beside install-stop's `stopped` marker, probed after
  its disarm, so `stage_armed`, `sudo_passwordless`, `keyfile_present` and `luks_keyslots` keep their values) with its
  banner and the rows of `scenarios.nuon`'s `stopped` at theirs. `dot status` FAIL checks print as notes.
- A pass destroys the VM; a failure keeps it for inspection and prints the `dot test destroy --name` line.

## While and after

```bash
dot test shot      # $XDG_CACHE_HOME/vm-test/<name>/screen.png
dot test destroy   # VM, disk, NVRAM, passt, pasta and socat; the cached iso stays
```

Serial console `serial.log`, channel `report.log`, both in the cache dir. A viewer goes on a headless output
(`l-dotfiles-gui-testing`); `virsh -c qemu:///session send-key` types on the console without one.
