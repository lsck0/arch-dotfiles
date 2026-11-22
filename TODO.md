# TODO

## Needs Luca

1. Reboot luca-pc and luca-notebook: their boot chains now ask for the YubiKey (FIDO2) at LUKS unlock; the passphrase
   still works as fallback. `dot status` drops its `luks` note after that boot.
2. Wazuh: copy `wazuh-enrollment-password` from the homelab sops (homelab TODO.md, "Needs Luca") to
   `configs/secrets/keys/wazuh-enrollment-password` and `dot sync` (pushes the pkgbuild; removes OSSEC here). Once the
   mirror carries `wazuh-agent`, `dot sync` on luca-pc and luca-notebook installs, enrolls and starts the agent.
3. Record the secrets recovery drill: configs/secrets/yubikey/RECOVERY.md "Test it", then `dot secrets audit drilled`.
4. Once the mirror carries `exiled-exchange-2-bin` (below): `dot apply --packages` on luca-pc.

## Waiting on homelab

- `exiled-exchange-2-bin`: queued in the running archbuild; `lsck0.db` gets it when that run publishes.
- `wazuh-agent`: new own pkgbuild, built by the mirror's next run.
