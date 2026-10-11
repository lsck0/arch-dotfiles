# Rolling back with timeshift

Timeshift snapshots `@` (the root subvolume) weekly, four kept, and before each pacman upgrade
(timeshift-autosnap), three kept. `@home`, `@log`, `@pkg` and the other top-level subvolumes are not in them and
never roll back. Neither does the ESP at `/boot`: its kernels, UKIs and systemd-boot stay at their newest.

That is the catch. A snapshot from before a kernel upgrade holds the older `/usr/lib/modules`, while systemd-boot
still boots the newer UKI. The kernel boots, finds no modules (amdgpu, network, ...) and leaves a bare console.
`kernel-resync.service` handles this at boot: it copies each installed kernel back onto the ESP, rebuilds its UKI
(sbctl's mkinitcpio hook signs it) and reboots once into the matching kernel.

## The system still boots

```bash
sudo timeshift --list
sudo timeshift --restore --snapshot '<YYYY-MM-DD_HH-MM-SS>'
reboot   # kernel-resync may reboot a second time on its own
```

If the resync failed (`journalctl -b -u kernel-resync`), pick the `linux-lts` entry in systemd-boot's menu when that
kernel was not upgraded in the same transaction, or log in on a console and run `sudo kernel-resync`.

## The system does not boot: from the Arch ISO

```bash
cryptsetup open /dev/nvme0n1p2 root               # LUKS name: rd.luks.name=<uuid>=<name> in /etc/kernel/cmdline
mount -o subvolid=5 /dev/mapper/root /mnt         # the top level, where @ and the snapshots live
ls /mnt/timeshift-btrfs/snapshots/                # <date>/info.json says why each was taken
mv /mnt/@ /mnt/@broken
btrfs subvolume snapshot /mnt/timeshift-btrfs/snapshots/<date>/@ /mnt/@
umount /mnt

mount -o subvol=@ /dev/mapper/root /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt kernel-resync                    # the ESP's kernels and UKIs back in step with this @
umount -R /mnt
reboot
```

Without `kernel-resync` (a snapshot taken before this module installed it), do the same by hand inside
`arch-chroot /mnt`:

```bash
for f in /usr/lib/modules/*/pkgbase; do install -m644 "${f%/*}/vmlinuz" "/boot/vmlinuz-$(<"$f")"; done
mkinitcpio -P
```

Once the restored system runs well, delete the old root from the top level: `btrfs subvolume delete
/mnt/@broken` (mounted with `subvolid=5` again). Subvolumes nested inside `@`, such as `/var/lib/machines`, stayed
in `@broken`; move anything you need out of them first.
