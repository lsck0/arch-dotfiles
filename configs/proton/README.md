# Proton ecosystem (Proton Unlimited)

Tooling, systemd `--user` units and config templates for Proton VPN and Pass.
**Everything auth-related is a manual step you run yourself**: this scaffold
never stores credentials, and this repo is PUBLIC.

- Secrets never live here. Pass uses the system keyring / GPG, and anything you
  must keep in-repo goes in the private `configs/secrets` submodule, not here.
- `configs/proton/.gitignore` blocks the obvious footguns (`*.env`, `*.token`).
- Each tool has its own `link.sh` (run by the top-level `install.sh` link loop).
  The units are installed disabled/idle where a login is required first, so a
  fresh `install.sh` never fails on a not-yet-authenticated Proton service.

Proton Drive is not set up on this machine: the homelab NAS (vm-109) mirrors
everything but its media disk to `homelab-offsite/` with rclone, so no local client is needed.

## Packages added to `install.sh`

| Package | Group | Purpose |
| --- | --- | --- |
| `proton-vpn-cli` | base | `protonvpn` CLI used by `toggles/toggle-protonvpn.sh` |
| `pass-otp` | base | `pass otp` TOTP extension |
| `proton-pass` | desktop | Proton Pass desktop app |

`pass` was already in `[base]`.

---

## Proton VPN

Already wired: `toggles/toggle-protonvpn.sh` toggles the tunnel via the
`protonvpn` CLI (from `proton-vpn-cli`). Note it stops `portmaster.service` and
swaps in a ufw ruleset while connected, because Portmaster's NFQUEUE interception
conflicts with ProtonVPN's fwmark policy routing.

**Manual auth step, sign in once:**

```
protonvpn signin
```

After that the toggle (bar widget / `toggle-protonvpn.sh`) connects and
disconnects. If it reports "Authentication required", run `protonvpn signin`
again. The GUI (`proton-vpn-qt-app`) is also installed if you prefer it.

---

## TOTP + Proton Pass

Two independent things:

- **`pass` + `pass-otp`**: your local GPG-encrypted store, with `pass otp` for
  TOTP. Setup (`pass/link.sh` only checks, never touches secrets):

  ```
  gpg --import   # import your key, e.g. from the configs/secrets submodule
  pass init <your-gpg-key-id>
  pass otp insert proton/totp   # paste the otpauth:// URI from Proton
  pass otp proton/totp          # prints the current code
  ```

  The GPG key is the secret: keep it in `configs/secrets` (private submodule)
  or your keyring, never in this repo.

- **Proton Pass** (`proton-pass` desktop app): Proton's own vault, which also
  holds TOTP secrets. Auth is interactive in the app: launch `proton-pass` and
  sign in with your Proton account (+ 2FA).

---

## Manual auth steps, in order

1. `protonvpn signin` (once): the toggle handles connect/disconnect after.
2. `gpg --import` + `pass init <key-id>` for `pass`/`pass-otp`, and sign in to
   the `proton-pass` app for the Proton Pass vault.
