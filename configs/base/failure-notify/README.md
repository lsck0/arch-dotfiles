# failure-notify

Everything that should reach the admin as a desktop notification instead of only the journal:

- a failed user service: `OnFailure=failure-notify@%n` on every user service (`mod.nu` link)
- a dotfiles run that left `FAILURES.*`: `failures-login.service` at login
- `system-notify` follows the system journal (wheel reads it) for a failed system unit, smartd's disk warnings
  (configs/base/smartd) and root's reports under the identifier `dotfiles-health`, such as the monthly
  `lynis-audit` (`mod.nu` system); a unit failing over and over shows at most hourly
- `update-check`, daily: once per new package set, how many updates the lsck0 snapshot has and which installed
  packages have an arch security advisory with a fix
- `doctor-check`, hourly: `dot status --brief` into `~/.local/state/doctor/findings`, which the bar's doctor
  indicator shows while it is not empty; a notification only when the findings become a set not notified before
  (ages and counts ignored). It also publishes this machine's drift report for `dot status`
- `recovery-drill`, monthly for a `secrets` profile: a reminder once the paper-key drill (RECOVERY.md, "Test it") is
  a year old or was never recorded; `dot secrets audit drilled` records it
