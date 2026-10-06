# syncthing

Syncs `~/sync` with the homelab NAS (`vm-109-nas`, `10.100.0.109` over the
wireguard tunnel).

`link.sh` installs `configs/base/secrets/syncthing/<hostname>/` (`cert.pem`,
`key.pem`, `config.xml`) so the device comes up paired. Without them it starts
a fresh identity; pair it at http://127.0.0.1:8384 and add its ID on the NAS.
Never share a device ID between two machines.
