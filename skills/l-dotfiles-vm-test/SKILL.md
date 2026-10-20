---
name: l-dotfiles-vm-test
description: "The end-to-end test, dot test run: bootstrap from the Arch ISO in a libvirt VM through the whole unattended chain, plus its logs, screenshot and teardown. Takes hours. Load before testing a fresh install or the install stages."
---

# vm-test

`dot test run` creates a system libvirt VM (`qemu:///system`, Secure Boot in Setup Mode, 200 GiB disk), types
`bootstrap.sh` into the ISO console, waits for `dot internal stage` to run `dot apply --packages` and `dot apply` on
their own boots, logs in on tty3, pulls logs and checks the end state. Install plus config can take up to 12 h.

## Before

- `dot test lint` (also run first by `run`).
- Needs sudo (asked once, kept alive), `virt-install`, `virsh`, `tesseract`, `magick`, `socat` (the beacon server), and the ISO at
  `~/downloads/archlinux-x86_64.iso` (`--iso PATH` otherwise).
- `--iso` with an Arch Linux-LSCK0 iso (`dot internal iso`, told apart by its `ARCH_LSCK0_` volume label) types
  nothing: the answers, the snapshot bundle and its lfs objects go on a second cd labelled `LSCK0` (`lsck0.nuon`,
  `unattended: true`); the iso's stub fetches and verifies GitHub master, applies the bundle on top (so the second
  stage `dot internal iso-install` and everything after come from the local tree), and its `install: failed` line on
  tty1 fails the run (the bootstrap's log is the guest's `/tmp/lsck0-install.log`). Also needs `xorriso` (archiso pulls it in).
- It tests the local working tree, untracked files included, as a bundle on top of `origin/master`; `--master`
  tests GitHub master instead.

## Run

```bash
dot test run                              # platforms/test-vm.nuon, login luca, profile luca
dot test run --platform luca-notebook     # another platform file
dot test run --profile custom             # no profile: nothing personal
dot test run --platform server            # the server path (hostname, groups, ssh key from BOOTSTRAP_*)
dot test run --name other-vm              # a second VM beside the default archlinux-test
```

Run it in the background; it prints progress and exits 1 with the problems.

## While and after

```bash
dot test shot      # ~/.cache/vm-test/<name>/screen.png, read it to see the console
dot test logs      # logs in on tty3 again, pulls stage logs, FAILURES.*, every *.log into ~/.cache/vm-test/<name>/logs, plus the verdict
dot test type 'text\n'                    # type on the console (de layout, --layout us on the ISO)
dot test destroy   # delete the VM and its disk, the ISO volume stays
dot test drill egress    # on the VM a passed run left: portmaster bypass marks and the protonvpn netns kill switch
dot test drill rollback  # kernel downgrade, timeshift snapshot, upgrade, restore; kernel-resync must bring the ESP back
```

Pass: `dot test: chain succeeded`. Otherwise read `logs/FAILURES.*`, `logs/stage.log` and the failing module's
`*.log`. The verdict wants stage armed no, passwordless sudo no, no keyfile, one LUKS keyslot, Secure Boot on, the PDF print queue present.

`dot test shot` reads the VM framebuffer into a PNG with no window, so an agent watches the run through it. A
graphical viewer (virt-viewer) opened only to verify goes on the agent's own headless output (skill
`l-dotfiles-gui-testing`).
