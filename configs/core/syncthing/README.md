# syncthing

Syncs `~/sync` with the homelab NAS (`vm-104-nas`, `10.100.0.104` over the
wireguard tunnel), with staggered versioning (30 days) for what another device
deletes or overwrites.

The link verb installs `configs/secrets/keys/syncthing/<hostname>/` (`cert.pem`,
`key.pem`, `config.xml`) so the device comes up paired. Without them it starts
a fresh identity; pair it at http://127.0.0.1:8384 and add its ID on the NAS.
Never share a device ID between two machines.

Whatever `config.xml` says, it then turns off global and local discovery,
relays, NAT traversal, crash and usage reporting through the API, and sets the
GUI login to your user name with the password from
`configs/secrets/keys/syncthing-gui-password` (base64 characters only), or one it generates
into `~/.local/state/syncthing/gui-password` (0600) while that secret is missing.
