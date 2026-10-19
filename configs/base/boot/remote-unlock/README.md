# Remote LUKS unlock (initramfs SSH)

Unlock the root disk over the network: Wake-on-LAN the machine, SSH into the systemd initramfs, type the LUKS
passphrase, and boot continues. The on-console passphrase/YubiKey prompt is untouched and remains the local fallback,
so a misconfigured remote unlock never bricks boot.

Built on `mkinitcpio-systemd-tool` + `tinyssh`: a `systemd-networkd` link and a `tinysshd` run inside the initramfs,
both carrying `ConditionPathExists=/etc/initrd-release` so they only ever run in early boot, never on the live system.

## Enabling

Per machine, opt in:

- `platforms/<host>.options.nuon`: `"base/boot/remote-unlock": {ssh_unlock: true}`
- `platforms/<host>.nuon`: add `mkinitcpio-systemd-tool tinyssh tinyssh-convert busybox` to `extra_packages`

A laptop off its cable also joins a home wifi in the initramfs: set `wifi` too
(`"base/boot/remote-unlock": {ssh_unlock: true, wifi: true}`). `dot apply` turns every line of `secrets/wifi` (ssid, a
tab, the passphrase; already in `SYSTEM_SECRETS`) into a `wpa_supplicant` network, the key hashed by `wpa_passphrase`,
in `/etc/mkinitcpio-systemd-tool/config/initrd-wifi.conf`; `initrd-wifi.service` runs `wpa_supplicant` on the first
wireless interface the driver brings up. It uses the card's own mac, as NetworkManager does for the home wifis
(`base/networkmanager`), so the dhcp lease is the running system's.

`luca-pc` has both; `luca-notebook` adds `wifi`. Unsetting the option and re-running `dot apply` removes the wiring (disables the units, drops the
`systemd-tool` hook and `rd.neednet`).

## What `mod.nu` does

- `systemctl enable initrd-network.service initrd-tinysshd.service` (the enable symlinks are what the install hook scans;
  the units' condition keeps them initramfs-only).
- Installs the DHCP `.network` (`Name=en* wl*`), the tinyssh port drop-in (**port 2223**), and `openssh_key_convert=false`.
- Installs the dedicated initramfs host key to `/etc/tinyssh/sshkeydir` and the authorized key (`secrets/ssh_publickey.asc`)
  to `/etc/mkinitcpio-systemd-tool/config/authorized_keys`, which `initrd-shell.service` copies to the image's
  `/root/.ssh/authorized_keys`; the real root gets no key. The image's `/root/.profile` is upstream's `initrd-shell.sh`,
  the password agent an ssh login lands in.
- Adds the `systemd-tool` hook after `sd-encrypt` and `rd.neednet=1` to the kernel cmdline.
- The initramfs rebuilds at `system-apply`'s boot barrier (`BOOT_INPUTS`).

## Secrets

Both are in `SYSTEM_SECRETS` (`scripts/lib/system.nu`): `dot apply` streams them to the root step as data, the root copy
carries no `secrets/`.

- `secrets/ssh_publickey.asc`: already present, the key allowed to log in to the initramfs sshd.
- `secrets/initramfs-ssh/<host>/sshkeydir/`: the dedicated initramfs tinyssh host key. If absent, the first `dot apply`
  generates one at `/etc/tinyssh/sshkeydir` and prints the backup command; commit it so reinstalls keep the same host key:

  ```
  sudo mkdir -p secrets/initramfs-ssh/$(uname -n)
  sudo cp -a /etc/tinyssh/sshkeydir secrets/initramfs-ssh/$(uname -n)/sshkeydir
  # then dot sync
  ```

## Using it

```
wg-quick up <homelab>        # or be on the home LAN
wake-pc                      # or: ssh root@192.168.178.29 wol-pc
# ~15-30 s later the box is at the LUKS prompt in the initramfs:
ssh -p 2223 root@<pc-ip>     # new known_hosts entry (distinct host key); the agent prompts, type the passphrase
# boot continues; once up:
sshk luca@<pc-ip>             # the real sshd, knocked open on 2222
```

`Ctrl-C` at the prompt opens `initrd-shell.sh`'s menu; `journalctl -b -t shell` shows its log after boot.

## First boot: verify at the machine

This touches the initramfs; test the first reboot **at the machine**, with the console reachable, so the passphrase
fallback is right there if anything is off:

1. `dot apply` (rebuilds the UKI), then reboot.
2. The console still shows the normal passphrase/YubiKey prompt; confirm it still unlocks locally.
3. From another host on the LAN (or over WireGuard): `ssh -p 2223 root@<pc-ip>`, enter the passphrase, confirm boot continues.
4. Confirm the host key is the committed one (`secrets/initramfs-ssh/<host>/sshkeydir/ed25519.pk`, via `tinysshd-printkey`).

## Security

- tinyssh is key-only (no passwords); only `secrets/ssh_publickey.asc` may log in.
- The initramfs sshd is up only during the unlock window (it is gone once the real system boots).
- During that window it is reachable on the LAN / WireGuard subnet on port 2223. It does nothing but drive the password
  agent for the root volume.
- With `wifi` the image carries the home wifis' keys (as wpa_passphrase's hash, which joins the network as well as the
  passphrase does). The image sits unencrypted on the ESP, so whoever holds the disk can join that wifi.
