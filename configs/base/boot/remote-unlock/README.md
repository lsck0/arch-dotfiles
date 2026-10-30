# Remote LUKS unlock

Wake the machine, ssh into the initramfs (tinysshd on port 2223), type the LUKS passphrase. The console prompt stays as
the local fallback. Units carry `ConditionPathExists=/etc/initrd-release`, so they never run on the live system.

Enable per machine in `platforms/<name>.options.nuon`: `"base/boot/remote-unlock": {ssh_unlock: true}` (`wifi: true`
to also join the home wifis from `configs/secrets/keys/wifi`). The module then declares its packages itself; unsetting
the option and `dot apply` removes it again.

Secrets:

- `configs/secrets/keys/wifi`: the home wifi keys, only with `wifi: true` (in `SYSTEM_SECRETS`).
- `configs/secrets/keys/ssh_publickey.asc`: the only key allowed to log in (in `SYSTEM_SECRETS`).
- `configs/secrets/keys/initramfs-ssh/<host>/sshkeydir/`: the initramfs host key, carried separately from
  `SYSTEM_SECRETS`. If absent, the first apply generates one and prints the backup command (copy, then `chown` to your
  user so `dot sync` can commit it).

Use:

```
wake-pc                      # or on the LAN: ssh root@<router> wol-pc (ssh's wake_router host)
ssh -p 2223 root@<pc-ip>     # type the passphrase, boot continues
sshk <user>@<pc-ip>          # the real sshd on base/ssh.port afterwards
```

`Ctrl-C` at the prompt opens the initrd shell menu; `journalctl -b -t shell` shows its log.

Test the first reboot at the machine, so the console fallback is at hand.

With `wifi`, the image on the unencrypted ESP carries the home wifi keys: whoever holds the disk can join that wifi.
