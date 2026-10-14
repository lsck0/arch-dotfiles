# VeraCrypt vault

Container `~/sync/vault.hc` (synced by syncthing), mounted at `~/vault` (not
synced). `mod.nu` links `veracrypt-vault.nu` to `~/.local/bin/veracrypt-vault`
and, while there is no container yet, prints the command to create it: the password
prompt needs a terminal, which an apply never has.

```
veracrypt-vault create [size]   # once, default 1G
veracrypt-vault mount
veracrypt-vault umount
veracrypt-vault status
```

Do not mount it on two machines at once. Never commit the container.
