---
name: l-dotfiles-vm-test
description: "The end-to-end install test, dot test run: the lsck0 iso with an answer file in a libvirt session VM through the whole unattended chain, scenarios, the chain's report, shot and destroy. Takes hours. Load before testing a fresh install, the install stages or bootstrap changes. Reading a real machine's stopped chain is l-dotfiles-install."
---

# vm-test

`dot test run` runs as the user, no sudo, up to 12 h. Disk, NVRAM, answers, logs and the report channel live in
`$XDG_CACHE_HOME/vm-test/<name>/` (default name `archlinux-test`).

## Run

1. Needs: the `kvm` group, `virt-install`, `virsh`, `passt`, `pasta`, `socat`, `xorriso`, `curl`; `magick` for `shot`.
2. It tests the working tree (untracked files included) as a bundle over `origin/master`; `--master` tests GitHub
   master. The iso is the published one, fetched and verified; `--iso PATH` boots a local build.
3. Start it in the background; `run` runs `dot test lint` first, prints each beacon and exits 1 with the problems.

```bash
dot test run                              # platform vm, login luca, profile luca, scenario home
dot test run --platform luca-notebook --profile custom
dot test run --scenario off-home,public-mirror
dot test run --scenario all --dry-run     # each run's answers, network and snapshot edits; boots nothing
dot test run --name other-vm              # beside the default VM
dot test run --iso "${XDG_CACHE_HOME:-$HOME/.cache}"/dotfiles-iso/out/archlinux-lsck0-latest-x86_64.iso
```

## Scenarios

`--scenario` takes a comma list from `scripts/lib/vm/scenarios.nuon`, layered over `home`; two that disagree
(`home,off-home`) are refused. `all` runs each scenario and preset alone, one fresh VM each, in a row.

| scenario | condition |
|---|---|
| `home` | `home_network: true`: the install records passt's gateway as home |
| `off-home` | `home_network: false`; host lan, lab subnets and IPv6 blocked, dns 9.9.9.9 |
| `secrets-locked` | profile `luca`, no YubiKey reaches the guest; wants the secrets banner |
| `public-mirror` | the lab blocked, dns 9.9.9.9 |
| `pkg-fail` | an unresolvable `extra_packages` entry; install `failed`, `planted_dropped` |
| `no-tor` | `base/tor` declares a missing package in place of `tor`; as pkg-fail, plus `tor_installed=no` |
| `lab-down` | profile `custom`, off-home plus `mirror.lsck0.dev` blocked; `lsck0_dropped=yes` |
| `config-fail` | `core/btop`'s `link` throws: config `failed`, the chain disarmed, `config_banner=yes` |
| `notebook-2026-10-30` | preset: off-home, secrets-locked, public-mirror on `luca-notebook` |

`pkg-fail`, `no-tor` and `config-fail` edit the snapshot, so they refuse `--master`. A snapshot `replace` whose pattern
no longer matches stops the run (and `vm.test.nu` in lint), so a refactor cannot void a scenario.

## Read the result

- Pass prints `dot test: <scenario>: chain succeeded` and destroys the VM. A failure keeps the VM and prints its
  `dot test destroy --name <name>` line; in a series only the last failure keeps its VM.
- The report: `$XDG_CACHE_HOME/vm-test/<name>/logs/<scenario>` (`status.json`, journals, `FAILURES.*`, invariants).
- Install failed: `host/upload/bootstrap.log` in the cache dir. A power-off without `bootstrap-ok`, or a guest down
  mid-chain with no verdict, is a crash: read `serial.log`.
- Live: `dot test shot` writes `screen.png` in the cache dir; `serial.log` and `report.log` (virtio channel) beside
  it. `virsh -c qemu:///session send-key` types on the console. A viewer goes on a headless output
  (`l-dotfiles-gui-testing`).

Read [reference.md](reference.md) for the VM and network setup, the beacons and the exact pass criteria.

## Teardown

`dot test destroy [--name <name>]` removes the VM, disk, NVRAM, passt, pasta and socat; the cached iso stays. A ctrl+c
leaves socat and pasta running until the next run or destroy stops them by pidfile.
