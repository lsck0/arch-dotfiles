# failure-notify

Everything that should reach the admin as a desktop notification instead of only the journal:

- a failed user service: `OnFailure=failure-notify@%n` on every user service (`link.sh`)
- a dotfiles run that left `FAILURES.*`: `failures-login.service` at login
- `system-notify` follows the system journal (wheel reads it) for a failed system unit, smartd's disk warnings
  (configs/base/smartd) and root's reports under the identifier `dotfiles-health`, such as the monthly
  `lynis-audit` (`system.sh`); a unit failing over and over shows at most hourly
- `update-check`, daily: once per new package set, how many updates the lsck0 snapshot has and which installed
  packages have an arch security advisory with a fix
