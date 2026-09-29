# syncthing

The shared folder is `~/sync`, synced device-to-device (mutual TLS, no cloud).
It pairs with the homelab NAS (`vm-109-nas`); the NAS handles the offsite copy.

Reachability off the home network relies on the homelab wireguard tunnel (the
NAS lives on `10.100.0.109`); global discovery + relays are enabled as a
fallback but are not guaranteed.

## Reproducing the device

`link.sh` reproduces the authed device from the private secrets submodule when
this host's identity is present:

- `configs/secrets/syncthing/<hostname>/` holds `cert.pem`, `key.pem` (the
  device ID) and `config.xml` (paired devices + the folder). `link.sh` installs
  them into `~/.local/state/syncthing/` before the service starts, so it comes
  up already paired. The database and GUI TLS cert regenerate on their own.
- No secrets for this host: `link.sh` starts a fresh identity, creates the
  `sync` folder via the API, and device pairing is manual in the UI
  (http://127.0.0.1:8384). Add the new device's ID on the NAS to finish.

Each host gets its own `cert.pem`/`key.pem` (never share a device ID between two
machines). The GUI has no password and binds to localhost only.
