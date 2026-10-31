# syncthing

Syncs `~/sync` with the homelab NAS (`nas.syncthing` in `platforms/homelab.nu`, LAN or wireguard), 30 days staggered versioning.

Identity from `configs/secrets/keys/syncthing/<hostname>/` (`cert.pem`, `key.pem`, `config.xml`); without it a new
device ID to pair at http://127.0.0.1:8384. Never share a device ID between machines. Discovery, relays, NAT and
reporting are off; the GUI password comes from `configs/secrets/keys/syncthing-gui-password` or is generated into
`~/.local/state/syncthing/gui-password`.
