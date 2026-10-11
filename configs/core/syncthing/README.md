# syncthing

Syncs `~/sync` with the homelab NAS (`vm-109-nas`, `10.100.0.109` over the
wireguard tunnel), with staggered versioning (30 days) for what another device
deletes or overwrites, and sends `~/.local/share/borg-repo` as the folder
`borg-<host>` to the NAS alone (configs/core/borg).

`link.sh` installs `secrets/syncthing/<hostname>/` (`cert.pem`,
`key.pem`, `config.xml`) so the device comes up paired. Without them it starts
a fresh identity; pair it at http://127.0.0.1:8384 and add its ID on the NAS.
Never share a device ID between two machines.

Whatever `config.xml` says, `link.sh` then turns off global and local discovery,
relays, NAT traversal, crash and usage reporting through the API, and sets the
GUI login to your user name with the password from
`secrets/syncthing-gui-password` (base64 characters only), or one it generates
into `~/.local/state/syncthing/gui-password` (0600) while that secret is missing.

On the NAS, accept `borg-<host>` as receive-only with versioning off: the repo
is already encrypted and versioned by borg itself.
