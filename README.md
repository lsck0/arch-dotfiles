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

### Getting the layout right in archinstall

All three features are decided at install time. Reaching them afterwards means
a reinstall or a backup-and-restore, so set the disk up this way from the
start. In `archinstall`, under **Disk configuration**:

1. **Partitioning → Use a best-effort default partition layout**, then pick the
   disk. Answer the follow-up prompts as below rather than accepting the
   defaults.
2. **Filesystem: `btrfs`.** When asked *"Would you like to use BTRFS
   subvolumes with a default structure?"* answer **yes**. That is what creates
   `@`, `@home`, `@log`, `@pkg` and `@.snapshots` and mounts root from `@` —
   the named-subvolume requirement in the table above. Answering no leaves root
   on `subvolid=5` and `configs/boot/timeshift/link.sh` will refuse to
   configure btrfs mode.
3. **"Would you like to use BTRFS compression?" → yes.** `compress=zstd`
   happens before encryption, so it is the one setting that buys back some of
   what LUKS costs.
4. **Disk encryption → LUKS**, encryption type *LUKS on partition*, and select
   the **root partition** (not the boot partition — the ESP must stay
   unencrypted). Set a passphrase you can type on the initramfs keymap. This
   is the `luks` feature's precondition; there is no supported way to add it
   later without rewriting the disk.
5. **Boot: UEFI.** Boot the installer in UEFI mode (an installer booted in
   BIOS/CSM mode silently produces an MBR disk with no ESP, and Secure Boot is
   then unreachable). archinstall creates a GPT disk with a FAT32 ESP at
   `/boot` automatically when the firmware is in UEFI mode — confirm
   `/sys/firmware/efi` exists in the live environment **before** starting.
   Leave Secure Boot **off** in firmware for the install; `sbctl` enrolls keys
   afterwards, and the firmware has to be in Setup Mode for that.
6. **Bootloader**: Limine or systemd-boot both work. Bootable snapshots from
   the boot menu are a GRUB-only feature (`grub-btrfs`) — with the others,
   restoring a snapshot means a live USB and `timeshift --restore`.

After the first boot, clone this repo and run `install.sh`; at the boot-feature
prompt select all three. What each script then does — and what it deliberately
leaves to you — is the table above.

#### Manual LUKS format (for the format-time tunables)

The cipher, key size, PBKDF and **sector size** live in the LUKS2 header and
are fixed at `luksFormat`. Nothing changes them afterwards — `--sector-size`
in particular needs a full `cryptsetup reencrypt` of the whole disk — and
`install.sh` never runs `luksFormat` (creating or reformatting a partition is
destructive and stays a deliberate manual step). archinstall does not expose
`--sector-size` either. So to get the tuned header, format the root partition
by hand in the live environment **before** starting archinstall, then point
archinstall's disk step at the already-open mapping.

`configs/boot/luks/link.sh` applies only the *open-time* options
(`discard`, `perf-no-{read,write}-workqueue`) through `/etc/crypttab`; the
`luksFormat` flags below are the ones it cannot set for you.

```bash
# In the Arch live environment, with a verified backup — this ERASES the
# partition. Replace nvme0n1p2 with your real root partition.

# 512e NVMe: --sector-size 4096 halves dm-crypt's per-bio overhead. On a native
# 4Kn drive it is already the default; on a 512-native drive, omit it.
cryptsetup luksFormat \
  --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 256 \
  --sector-size 4096 \
  --pbkdf argon2id \
  /dev/nvme0n1p2

# Open it; this name is what archinstall (and later /etc/crypttab) will use.
cryptsetup open /dev/nvme0n1p2 cryptroot

# Put btrfs inside the mapping, NOT on the raw partition.
mkfs.btrfs /dev/mapper/cryptroot
```

Now run archinstall and, in **Disk configuration → Partitioning**, use
*Pre-mounted configuration* (or select the existing `/dev/mapper/cryptroot`)
rather than letting it partition — otherwise it reformats and the tuned header
is gone. The btrfs-subvolume and compression answers from the list above still
apply, on top of the mapping.

`--allow-discards`, `--perf-no_read_workqueue`, `--perf-no_write_workqueue` are
deliberately **not** passed to `luksFormat` here: they are open-time behaviour,
and `configs/boot/luks/link.sh` sets them in `/etc/crypttab` so they persist
across reboots. `discard` (TRIM pass-through) keeps SSD performance and
wear-levelling healthy at the cost of revealing which blocks are free to
someone with the powered-off disk. Drop it from the script if that trade is
wrong for you.

## Screenshots

Amazing wallpapers: https://aenamiart.artstation.com/

![screenshot](https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/showcase/showcase1.png)
