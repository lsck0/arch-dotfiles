# Remote LUKS unlock (initramfs SSH)

Unlock the root disk over the network: Wake-on-LAN the machine, SSH into the systemd initramfs, type the LUKS
passphrase, and boot continues. The on-console passphrase/YubiKey prompt is untouched and remains the local fallback,
so a misconfigured remote unlock never bricks boot.

Built on `mkinitcpio-systemd-tool` + `tinyssh`: a `systemd-networkd` link and a `tinysshd` run inside the initramfs,
both carrying `ConditionPathExists=/etc/initrd-release` so they only ever run in early boot, never on the live system.

## Enabling

Per machine, opt in:

- `platforms/<host>.sh`: `REMOTE_UNLOCK=1`
- `platforms/<host>.sh`: add to `EXTRA_PACKAGES`: `mkinitcpio-systemd-tool tinyssh tinyssh-convert busybox`

`luca-pc` has both. Dropping `REMOTE_UNLOCK` and re-running `config.sh` removes the wiring (disables the units, drops the
`systemd-tool` hook and `rd.neednet`).

## What `system.sh` does

- `systemctl enable initrd-network.service initrd-tinysshd.service` (the enable symlinks are what the install hook scans;
  the units' condition keeps them initramfs-only).
- Installs the wired-NIC DHCP `.network` (`Name=en*`), the tinyssh port drop-in (**port 2223**), and `openssh_key_convert=false`.
- Installs the dedicated initramfs host key to `/etc/tinyssh/sshkeydir` and the authorized key (`secrets/ssh_publickey.asc`)
  to `/root/.ssh/authorized_keys` (inert on the live system — `PermitRootLogin no`), plus a `/root/.profile` that runs the
  password agent only under `/etc/initrd-release`.
- Adds the `systemd-tool` hook after `sd-encrypt` and `rd.neednet=1` to the kernel cmdline.
- The initramfs rebuilds at `system-apply`'s boot barrier (`BOOT_INPUTS`).

## Secrets

- `secrets/ssh_publickey.asc` — already present; the key allowed to log in to the initramfs sshd.
- `secrets/initramfs-ssh/<host>/sshkeydir/` — the dedicated initramfs tinyssh host key. If absent, the first `config.sh`
  generates one at `/etc/tinyssh/sshkeydir` and prints the backup command; commit it so reinstalls keep the same host key:

  ```
  sudo mkdir -p secrets/initramfs-ssh/$(uname -n)
  sudo cp -a /etc/tinyssh/sshkeydir secrets/initramfs-ssh/$(uname -n)/sshkeydir
  # then ./sync.sh
  ```

## Using it

```
wg-quick up <homelab>        # or be on the home LAN
wake-pc                      # or: ssh root@192.168.178.29 wol-pc
# ~15-30 s later the box is at the LUKS prompt in the initramfs:
ssh -p 2223 root@<pc-ip>     # new known_hosts entry (distinct host key); the agent prompts, type the passphrase
# boot continues; once up:
ssh luca@<pc-ip>
```

If `/root/.profile` does not auto-run the agent for your shell, run it by hand after logging in:
`systemd-tty-ask-password-agent --query --watch`.

## FIRST BOOT — verify with physical access available

This touches the initramfs; test the first reboot **at the machine**, with the console reachable, so the passphrase
fallback is right there if anything is off:

1. `config.sh` (rebuilds the UKI), then reboot.
2. At the console you still get the normal passphrase/YubiKey prompt — confirm it still unlocks locally. (Fallback intact.)
3. From another host on the LAN (or over WireGuard): `ssh -p 2223 root@<pc-ip>`, enter the passphrase, confirm boot continues.
4. Confirm the host key is the committed one (`secrets/initramfs-ssh/<host>/sshkeydir/ed25519.pk`, via `tinysshd-printkey`).

## Security

- tinyssh is key-only (no passwords); only `secrets/ssh_publickey.asc` may log in.
- The initramfs sshd is up only during the unlock window (it is gone once the real system boots).
- During that window it is reachable on the LAN / WireGuard subnet on port 2223. It does nothing but drive the password
  agent for the root volume.
