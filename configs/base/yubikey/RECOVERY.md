# Recovery

What gets back the secrets, the disks and the backups when a YubiKey, or every machine together with it, is gone.

## What opens what

| secret | opened by |
|---|---|
| `secrets/` (git-crypt) | `secrets.key.age`: every enrolled YubiKey (`age-<serial>.identity`) and every age recipient in `recipients.txt` |
| `secrets/` on a machine that already pulled it | also the PGP key in the local `~/.gnupg` (git-crypt's gpg user) |
| the private `secrets` repo itself | the YubiKey ssh stub, or https with a GitHub personal access token |
| root disk (LUKS) | the passphrase, then the enrolled YubiKey (FIDO2) and TPM2 + PIN; header copy in `secrets/luks-header-<host>.img` |
| `sudo` | the password; YubiKey PIN + touch and fingerprint are only shortcuts |
| homelab sops files | `secrets/age.txt` and every YubiKey identity |

## Keep offline

- The private half of the extra `recipients.txt` recipient (the paper age key), printed or on a drive in a safe. Without
  it, losing every enrolled YubiKey loses `secrets/`.
- GitHub 2FA recovery codes, and a way to make a personal access token (the `secrets` repo is private).
- The LUKS passphrase of every machine.
- The borg passphrase and the exported borg key (`borg key export`), on paper: kept in `secrets/`, they cannot be the
  way back into it.

## A second YubiKey

```bash
./scripts/lib/yubikey.sh unlock        # with the first key, or --identity below
./scripts/lib/yubikey.sh init          # second key plugged in: pins, pgp, ssh, u2f, age; reseals secrets.key.age
git add configs/base/yubikey && ./sync.sh
```

Then `./config.sh` on every machine (the new u2f line reaches `/etc/u2f_mappings`), and
`sudo systemd-cryptenroll --fido2-device=auto <luks partition>` with the second key on each. Keep it off-site.

## Every YubiKey lost

From the Arch ISO or any machine with `git`, `age` and `git-crypt`:

```bash
git clone https://github.com/lsck0/arch-dotfiles.git ~/projects/arch-dotfiles
cd ~/projects/arch-dotfiles
install -m600 /dev/null /dev/shm/paper.txt && $EDITOR /dev/shm/paper.txt   # the AGE-SECRET-KEY-1... line
./scripts/lib/yubikey.sh unlock --identity /dev/shm/paper.txt   # the token is the https password
shred -u /dev/shm/paper.txt
```

Then revoke the lost key: drop its `age-<serial>.identity`, `ssh-<serial>*` and its `u2f_keys` entry, run
`./scripts/lib/yubikey.sh seal`, remove its ssh key on GitHub, wipe its FIDO2 slot on every disk
(`sudo systemd-cryptenroll --wipe-slot=fido2 <partition>`), and enroll a replacement as above.

## Test it

Once a year, and after every reseal: in a scratch clone, `./scripts/lib/yubikey.sh unlock --identity <paper key>`
must turn `secrets/pgp_privatekey.asc` into plaintext. A paper key that fails here is no backup.

## LUKS header

`configs/base/boot/luks/header-backup.sh` writes the root header into `secrets/` after every keyslot change; commit
it. To restore: `cryptsetup luksHeaderRestore <partition> --header-backup-file luks-header-<host>.img` from the ISO,
then unlock with the passphrase that was valid when the copy was taken.
