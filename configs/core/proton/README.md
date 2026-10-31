# Proton

Sign in by hand once per machine:

1. `protonvpn signin`; afterwards `toggle-route proton` connects.
2. `pass`: core/gnupg imports the key and the store arrives through syncthing (`pass init <gpg-key-id>` only to start a
   brand-new store). TOTP codes live in Proton Authenticator, not in pass.
3. Start Proton Pass, Mail, Authenticator (and Meet, if used) and sign in.

## Sessions across a reinstall

`sessions` keeps those sign-ins for a reinstall of the same machine. `dot sync` backs up each app's session into
`configs/secrets/keys/proton/<host>/<app>.tar` (git-crypt): the session files under its state dir and, for Authenticator
and the VPN, its Secret Service items. Per host only: Proton rotates refresh tokens, so a session copied to a second
machine logs the first one out.

- Pass, Mail, Meet keep no key in the keyring: Mail and Meet store cookies in plain text, Pass with Chromium's fixed
  `basic` key, pinned through `--password-store=basic` in its desktop entry (else plasma would pick kwallet). The
  repo's git-crypt and the disk's LUKS are their protection, as for every other file in `~/.config`.
- Authenticator keeps its database key, the VPN (cli and qt app) its whole session in the login keyring: the backup
  carries those items, the restore re-creates them in the new keyring.
- Restore runs in `link` during the install chain (the keyring-free apps) and once at the first login through
  `proton-sessions-restore.service`, before `graphical-session.target`, once the pam-opened keyring is up. An app is
  restored only while nothing of its session is on the machine, so a newer sign-in is never replaced. Done once every
  app is settled (`~/.local/state/proton-sessions/restored`).
- The backup is as fresh as the last `dot sync`: run one right before reinstalling, and don't start the apps on the old
  install afterwards, or a rotated refresh token leaves the restored copy signed out.
