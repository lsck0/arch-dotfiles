---
name: l-dotfiles-vm-test
description: "The end-to-end test, dot test run: the lsck0 iso with an answer file in a libvirt VM through the whole unattended chain, the chain's own report, screenshot and teardown. Takes hours. Load before testing a fresh install or the install stages."
---

# vm-test

`dot test run` creates a libvirt VM (`qemu:///system`, Secure Boot in Setup Mode, 200 GiB) from the lsck0 iso plus a cd
labelled `LSCK0` with the answers (`lsck0.nuon`, `unattended: true`), the snapshot bundle and its lfs objects. The
guest reports to a socat server on the host (`scripts/lib/vm/serve.sh`, port 8765, `10.0.2.2` from the guest) via the
answers' `report` url. Up to 12 h.

## Before

- `dot test lint` (`run` runs it first).
- sudo (asked once), `virt-install`, `virsh`, `socat`, `xorriso`, `curl`; `magick` for `shot`.
- The iso: the published one, fetched to `~/.cache/vm-test/` and checked against `.sha256`; `--iso PATH` a local build.
- Tests the working tree (untracked included) as a bundle over `origin/master`; `--master` tests GitHub master. The
  stub applies the bundle and execs its own stub, so a published iso runs the current installer.

## Run

```bash
dot test run                              # platforms/vm.nuon, login luca, profile luca
dot test run --platform luca-notebook
dot test run --profile custom
dot test run --platform server
dot test run --name other-vm              # beside the default archlinux-test
dot test run --iso ~/.cache/dotfiles-iso/out/archlinux-lsck0-latest-x86_64.iso
```

Run it in the background; it prints each beacon and exits 1 with the problems.

## Reports

- Install powers the VM off when done; on failure the stub uploads `/tmp/lsck0-install.log` to
  `~/.cache/vm-test/<name>/host/upload/bootstrap.log` and beacons `bootstrap-fail`.
- Stages beacon `install-ok|failed`, `config-ok|failed` (`stage.nu`, `/var/lib/dotfiles-stage/report`).
- The chain's end runs `scripts/lib/stage-report.nu` as root: probes in `scripts/lib/invariants.txt`,
  `dot internal backup --roundtrip`, stage log, journals, `FAILURES.*`, `*.log`; uploads `logs.tgz`, beacons
  `chain-done`, reboots (waits at the passphrase; not unlocked).
- `~/.cache/vm-test/<name>/logs`: the report. Pass is `dot test: chain succeeded`, wanting `stage_armed=no`,
  `sudo_passwordless=no`, `keyfile_present=no`, `luks_keyslots=1`, `secure_boot=1`, `setup_mode=0`,
  `kernel_modules=yes`, `pdf_queue=yes`, `backup_roundtrip=ok`, both stages `ok`, no non-empty `FAILURES.*`.

## While and after

```bash
dot test shot      # ~/.cache/vm-test/<name>/screen.png
dot test destroy   # VM, disk, answers volume; the iso volume stays
```

Serial console: `/var/log/libvirt/qemu/<name>-serial.log` (root). A viewer goes on a headless output
(`l-dotfiles-gui-testing`).
