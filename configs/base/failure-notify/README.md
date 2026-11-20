# failure-notify

Desktop notifications for what would otherwise sit in the journal:

- a failed user service (`OnFailure=failure-notify@%N.service`), except kwalletd6 (KWallet is disabled here),
  an unnamed `systemd-run` job (`run-u*`, `run-p*`) and an offload job (`offload-*`), whose caller has its
  exit status;
- `FAILURES.*` from the last dot run, at login (`failures-login.service`);
- `system-notify`: failed system units, smartd warnings, `dotfiles-health` reports, at most hourly per unit or report;
- `update-check`, daily: pending updates and fixable security advisories;
- `lynis-audit`, monthly (root, where lynis is installed): the hardening index and the first warnings, logged as a
  `dotfiles-health` report that `system-notify` shows;
- `doctor-check`, hourly: `dot status --brief`, notified once per new set of findings;
- `recovery-drill`, monthly with secrets: reminder when the paper-key drill is over a year old
  (`dot secrets audit drilled` records it).
