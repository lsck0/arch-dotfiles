<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

TODO:

- cleanup scripts / toggles
- add new showcases

Run

```bash
mkdir -p ~/projects
git clone https://github.com/lsck0/arch-dotfiles.git ~/projects/arch-dotfiles/
cd ~/projects/arch-dotfiles/
./install.sh
```

after archinstall minimal and no applications (bluetooth, audio, etc) configured to setup the system.

## Things to do manually after rebooting

- add fingerprint with `fprintd-enroll` (once per device, persistent across reinstalls)

- run `spicetify backup apply && spicetify enable-devtools` after running spotify once (including logging in)

- run `betterdiscordctl install` after running discord once (including logging in)

- fetch the submodules (needs github auth, do `gh auth login`)

```bash
git submodule update --init --recursive
```

- import shh and pgp keys from secrets submodule

```bash
gpg --import ~/projects/arch-dotfiles/configs/secrets/pgp_privatekey.asc

sudo chmod 600 ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc
ssh-add ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc
```

- add wirguard vpn tunnel

```bash
sudo ln -sf ~/projects/arch-dotfiles/configs/secrets/wg0.laptop.conf /etc/wireguard/wg0.conf
```

## Boot disk security (btrfs subvolumes, timeshift, Secure Boot, LUKS)

`install.sh` prompts once (like package groups, state cached in `boot.conf`)
for which of `timeshift` / `sbctl` / `luks` to attempt. Each is **detected,
not assumed**: install.sh never partitions, converts MBR→GPT, or migrates an
unencrypted system into LUKS — partitioning and the bootloader are already
done by the time install.sh runs, on laptops, desktops, WSL, and servers
alike, so this only configures what the existing disk layout already
supports and otherwise prints what to fix and exits cleanly.

| Feature                | install.sh configures                                                                    | You must set up first                                                                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| timeshift (btrfs mode) | `/etc/timeshift/timeshift.json`, `timeshift-autosnap` pacman hook                        | root mounted from a **named** btrfs subvolume (e.g. `@`), not the top-level subvol (`subvolid=5`) — see ArchWiki Timeshift § Configuring btrfs snapshots |
| sbctl (Secure Boot)    | key creation + enrollment, signs the ESP boot chain, enables the mkinitcpio signing hook | a GPT disk with a real ESP, booted in UEFI mode (`/sys/firmware/efi` present)                                                                            |
| luks                   | `/etc/crypttab` tuning (`discard`, `perf-no-*-workqueue`), mkinitcpio `encrypt` hook     | an existing LUKS2 partition — install.sh will not encrypt an unencrypted root in place                                                                   |

If your system doesn't meet a precondition yet, `configs/boot/<feature>/link.sh`
says so on stderr and skips; rerun install.sh (or just that script) once you've
fixed it. See `BOOT.md` for the full research/rationale behind these choices
(cipher/sector-size tuning, TPM2 auto-unlock, why LUKS-on-LVM was rejected,
etc.) — it documents one real migration plan, but the mechanics below apply
to any machine.

To convert an existing top-level-subvolume system to the `@`/`@home` layout
timeshift needs, or to add a LUKS2 layer to an existing partition, follow the
ArchWiki (Timeshift § Converting an installed system; dm-crypt § Encrypting
an entire system) — both are point-of-no-return operations to do deliberately
with a verified backup, not folded into an unattended install script.

## Screenshots

Amazing wallpapers: https://aenamiart.artstation.com/

![screenshot](https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/showcase/showcase1.png)
