# TODO

## Needs Luca

1. Host keys not backed up (ssh on luca-pc and luca-notebook, initramfs on luca-notebook) and both LUKS roots
   passphrase only: run `~/keys-and-luks.sh` on each machine (secrets unlocked; backs up, enrolls the YubiKey, applies,
   syncs), then delete it.
2. Once the mirror carries `exiled-exchange-2-bin` (below): `dot apply --packages` on luca-pc.

## Waiting on homelab

- `exiled-exchange-2-bin`: queued in the running archbuild; `lsck0.db` gets it when that run publishes.
- Wazuh agent (`base/wazuh`, retiring `base/ossec`): homelab sends the lab.json keys and the
  `wazuh-enrollment-password` secret once the enrollment service is live; build then.
