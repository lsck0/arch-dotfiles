# Proton ecosystem (Proton Unlimited)

Tooling, systemd `--user` units and config templates for Proton Drive,
VPN and Pass. **Everything auth-related is a manual step you run yourself** —
this scaffold never stores credentials, and this repo is PUBLIC.

- Secrets never live here. rclone writes its config to `~/.config/rclone/`,
  Pass uses the system keyring / GPG, and anything you must
  keep in-repo goes in the private `configs/secrets` submodule, not here.
- `configs/proton/.gitignore` blocks the obvious footguns (`rclone.conf`,
  `*.env`, `*.token`).
- Each tool has its own `link.sh` (run by the top-level `install.sh` link loop).
  The units are installed disabled/idle where a login is required first, so a
  fresh `install.sh` never fails on a not-yet-authenticated Proton service.

## Packages added to `install.sh`

| Package | Group | Purpose |
| --- | --- | --- |
| `proton-vpn-cli` | base | `protonvpn` CLI used by `toggles/toggle-protonvpn.sh` |
| `pass-otp` | base | `pass otp` TOTP extension |
| `proton-pass` | desktop | Proton Pass desktop app |

`rclone` and `pass` were already in `[base]`.

---

## 1. Proton Drive (rclone)

Mounts Proton Drive at `~/ProtonDrive` via a systemd `--user` unit, so it shows
up for nvim `snacks.explorer` and any file manager. A bisync timer is provided
as an alternative — use one OR the other, not both on the same directory.

Files: `drive/rclone.conf.template` (shape reference, no creds),
`drive/proton-drive.service` (mount), `drive/proton-drive-bisync.{sh,service,timer}`
(opt-in two-way sync), `drive/link.sh`.

**Manual auth step — run `rclone config`:**

```
rclone config
# n) New remote
# name> protondrive
# Storage> protondrive
# username> your Proton email
# password> your Proton password (rclone obscures it)
# 2fa> your current TOTP code, if 2FA is enabled
# (mailbox password> only if you use two-password mode)
```

Then start the mount:

```
systemctl --user enable --now proton-drive.service
ls ~/ProtonDrive
```

`link.sh` enables the mount automatically only once the `protondrive:` remote
exists; before that it prints the command above.

Bisync instead of a live mount:

```
systemctl --user enable --now proton-drive-bisync.timer
```

Requires FUSE (`fuse3`) for the mount path.

---

## 3. Proton VPN

Already wired: `toggles/toggle-protonvpn.sh` toggles the tunnel via the
`protonvpn` CLI (from `proton-vpn-cli`). Note it stops `portmaster.service` and
swaps in a ufw ruleset while connected, because Portmaster's NFQUEUE interception
conflicts with ProtonVPN's fwmark policy routing.

**Manual auth step — sign in once:**

```
protonvpn signin
```

After that the toggle (bar widget / `toggle-protonvpn.sh`) connects and
disconnects. If it reports "Authentication required", run `protonvpn signin`
again. The GUI (`proton-vpn-qt-app`) is also installed if you prefer it.

---

## 4. TOTP + Proton Pass

Two independent things:

- **`pass` + `pass-otp`** — your local GPG-encrypted store, with `pass otp` for
  TOTP. Setup (`pass/link.sh` only checks, never touches secrets):

  ```
  gpg --import   # import your key, e.g. from the configs/secrets submodule
  pass init <your-gpg-key-id>
  pass otp insert proton/totp   # paste the otpauth:// URI from Proton
  pass otp proton/totp          # prints the current code
  ```

  The GPG key is the secret — keep it in `configs/secrets` (private submodule)
  or your keyring, never in this repo.

- **Proton Pass** (`proton-pass` desktop app) — Proton's own vault, which also
  holds TOTP secrets. Auth is interactive in the app: launch `proton-pass` and
  sign in with your Proton account (+ 2FA).

---

## Manual auth steps, in order

1. `rclone config` — create the `protondrive:` remote, then
   `systemctl --user enable --now proton-drive.service`.
2. `protonvpn signin` (once) — the toggle handles connect/disconnect after.
3. `gpg --import` + `pass init <key-id>` for `pass`/`pass-otp`, and sign in to
   the `proton-pass` app for the Proton Pass vault.
