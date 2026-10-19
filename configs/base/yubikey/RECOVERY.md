# Recovery

What gets back the secrets, the disks and the backups when a YubiKey, or every machine together with it, is gone.

## What opens what

| secret | opened by |
|---|---|
| `secrets/` (git-crypt) | `secrets.key.age`: every enrolled YubiKey (`age-<serial>.identity`) and every age recipient in `recipients.txt` |
| `secrets/` on a machine that already pulled it | also the PGP key in the local `~/.gnupg` (git-crypt's gpg user) |
| the private `secrets` repo itself | the YubiKey ssh stub, or https with a GitHub personal access token |
| root disk (LUKS) | the passphrase, then the enrolled YubiKey (FIDO2) and TPM2 + PIN; header copy in `secrets/luks-header-<host>.img` |
| `sudo` | the password; a YubiKey touch and fingerprint are only shortcuts |
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
./scripts/dot.nu secrets unlock         # with the first key, or --identity below
./scripts/dot.nu secrets init           # second key plugged in: pins, pgp, ssh, u2f, age; reseals secrets.key.age
git add configs/base/yubikey && dot sync
```

Then `dot apply` on every machine (the new u2f line reaches `/etc/u2f_mappings`), and
`sudo systemd-cryptenroll --fido2-device=auto <luks partition>` with the second key on each. Keep it off-site.

## Every YubiKey lost

From the Arch ISO or any machine with `git`, `age` and `git-crypt`:

```bash
git clone https://github.com/lsck0/arch-dotfiles.git ~/projects/arch-dotfiles
cd ~/projects/arch-dotfiles
install -m600 /dev/null /dev/shm/paper.txt && $EDITOR /dev/shm/paper.txt   # the AGE-SECRET-KEY-1... line
./scripts/dot.nu secrets unlock --identity /dev/shm/paper.txt   # the token is the https password
shred -u /dev/shm/paper.txt
```

Then revoke the lost key: drop its `age-<serial>.identity`, `ssh-<serial>*` and its `u2f_keys` entry, run
`./scripts/dot.nu secrets seal`, remove its ssh key on GitHub, wipe its FIDO2 slot on every disk
(`sudo systemd-cryptenroll --wipe-slot=fido2 <partition>`), and enroll a replacement as above.

## Test it

Once a year, and after every reseal: in a scratch clone, `./scripts/dot.nu secrets unlock --identity <paper key>` must
turn `secrets/pgp_privatekey.asc` into plaintext. A paper key that fails here is no backup. After a passing test run
`dot secrets audit drilled`: it records the date, and the monthly `recovery-drill.timer` reminds you once a year is up.

## LUKS header

`configs/base/boot/luks/header-backup.nu` writes the root header into `secrets/` after every keyslot change; commit
it. To restore: `cryptsetup luksHeaderRestore <partition> --header-backup-file luks-header-<host>.img` from the ISO,
then unlock with the passphrase that was valid when the copy was taken.

## By hand, once per key

Steps that need the FIDO2 PIN or a touch, so no script runs them. `dot secrets init` already did pins, pgp, ssh, u2f and
age; what is left:

**Root disk.** Adds a FIDO2 token beside the passphrase slot, never in place of it:

```bash
sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes <luks partition>
sudo cryptsetup luksDump <luks partition> | grep -A2 '^Tokens'   # a systemd-fido2 token, keyslot 0 still there
dot apply                                   # luks/mod.nu sees the token: rd.luks.options gains fido2-device=auto
configs/base/boot/luks/header-backup.nu       # then commit secrets
```

`dot apply` prints the partition (`luks: no yubikey enrolled, ...`). Reboot once with the passphrase at hand: PIN and
touch with the key in, the passphrase prompt after 30 s without it.

**TOTP.** Each account from the old authenticator app as an otpauth URI or its base32 secret; `--touch` makes a code
wait for a touch:

```bash
ykman oath accounts uri 'otpauth://totp/Issuer:name?secret=...&issuer=Issuer'
ykman oath accounts add --touch 'Issuer:name' <base32 secret>
ykman oath access change                      # optional password, Yubico Authenticator can remember it
totp Issuer                                   # the code onto the clipboard
```

**PGP key.** Already on the card (signature, encryption, authentication), `gpg --card-status` shows them. A second key
gets it through `dot secrets init pgp`. The local keyring keeps its secret half: gnupg's module re-imports
`secrets/pgp_privatekey.asc` whenever secrets are unlocked, so a `gpg --delete-secret-keys` would not hold.

**Passkeys.** In Firefox or Chromium, never qutebrowser (it shows no PIN dialog): the site's security settings, "add
security key", then PIN and touch. PingID: its self-service device page, "Add device", Security Key, from the capgemini
Chromium profile.

**PIN prompts.** sudo and polkit dialogs ask "Please enter the PIN" first while the key is plugged in: the FIDO2 PIN,
not the password, then a touch. A wrong PIN costs one of 8 attempts (`ykman fido info`), 3 in a row want a replug, and
8 block FIDO2 until a reset that wipes u2f, the ssh key and every passkey. Unplugged, the password prompt comes
straight away.
