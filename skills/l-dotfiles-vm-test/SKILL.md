---
name: l-dotfiles-vm-test
description: "The end-to-end test, dot test run: the lsck0 iso with an answer file in a libvirt VM through the whole unattended chain, the chain's own report, screenshot and teardown. Takes hours. Load before testing a fresh install or the install stages."
---

# vm-test

`dot test run` creates a system libvirt VM (`qemu:///system`, Secure Boot in Setup Mode, 200 GiB disk) from the
lsck0 iso plus a second cd labelled `LSCK0` carrying the answers (`lsck0.nuon`, `unattended: true`), the snapshot
bundle and its lfs objects. Nothing is typed and nothing is read off the screen: the guest talks back to a socat
server on the host (`scripts/lib/vm/serve.sh`, port 8765, the guest sees it as `10.0.2.2`) through the answers'
`report` url. Install plus config can take up to 12 h.

## Before

- `dot test lint` (also run first by `run`).
- Needs sudo (asked once, kept alive), `virt-install`, `virsh`, `socat`, `xorriso`, `curl`; `magick` for `shot`.
- The iso: the published `https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso`, fetched into
  `~/.cache/vm-test/` and checked against its `.sha256`; `--iso PATH` takes a local `dot internal iso` build.
- It tests the local working tree, untracked files included, as a bundle on top of `origin/master`; `--master`
  tests GitHub master instead. The iso's stub verifies master, applies the bundle and execs the bundle's own stub,
  so a published iso still runs the repo's current installer.

## Run

```bash
dot test run                              # platforms/vm.nuon, login luca, profile luca
dot test run --platform notebook          # another platform file
dot test run --profile custom             # no profile: nothing personal
dot test run --platform server            # the server path: groups from platforms/server.nuon, rest BOOTSTRAP_*
dot test run --name other-vm              # a second VM beside the default archlinux-test
dot test run --iso ~/.cache/dotfiles-iso/out/archlinux-lsck0-latest-x86_64.iso
```

Run it in the background; it prints each beacon as it arrives and exits 1 with the problems.

## What reports what

- The iso's install powers the VM off when done; on failure the stub uploads `/tmp/lsck0-install.log` to
  `~/.cache/vm-test/<name>/host/upload/bootstrap.log` and beacons `bootstrap-fail`.
- Each stage beacons `install-ok|failed` and `config-ok|failed` (`stage.nu`, from `/var/lib/dotfiles-stage/report`,
  written by the bootstrap from `BOOTSTRAP_REPORT`).
- The chain's end, once disarmed, runs `scripts/lib/stage-report.nu` as root from the root copy: the probes in
  `scripts/lib/invariants.txt`, `dot internal backup --roundtrip` as the user, the stage log and journals, every
  `FAILURES.*` and `*.log` of the checkout; it uploads them as `logs.tgz`, beacons `chain-done` and reboots into the
  finished system (which waits at the disk passphrase; the test does not unlock it).
- `~/.cache/vm-test/<name>/logs` holds the unpacked report. Pass: `dot test: chain succeeded`. The verdict wants
  `stage_armed=no`, `sudo_passwordless=no`, `keyfile_present=no`, `luks_keyslots=1`, `secure_boot=1`,
  `setup_mode=0`, `kernel_modules=yes`, `pdf_queue=yes`, `backup_roundtrip=ok`, both stages `ok` in `stage.log`
  and no non-empty `FAILURES.*`.

## While and after

```bash
dot test shot      # ~/.cache/vm-test/<name>/screen.png from the VM framebuffer, read it to see the console
dot test destroy   # delete the VM, its disk and its answers volume, the iso volume stays
```

The serial console goes to `/var/log/libvirt/qemu/<name>-serial.log` (root). A graphical viewer (virt-viewer)
opened only to verify goes on the agent's own headless output (skill `l-dotfiles-gui-testing`).
