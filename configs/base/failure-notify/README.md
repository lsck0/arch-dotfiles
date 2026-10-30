# failure-notify

Desktop notifications for what would otherwise sit in the journal:

- a failed user service (`OnFailure=failure-notify@%n.service`; kwalletd6 is skipped, KWallet is disabled here);
- `FAILURES.*` from the last dot run, at login (`failures-login.service`);
- `system-notify`: failed system units, smartd warnings, `dotfiles-health` reports, at most hourly per unit;
- `update-check`, daily: pending updates and fixable security advisories;
- `lynis-audit`, monthly (root, where lynis is installed): the hardening index and the first warnings, logged as a
  `dotfiles-health` report that `system-notify` shows;
- `doctor-check`, hourly: `dot status --brief`, notified once per new set of findings;
- `recovery-drill`, monthly with secrets: reminder when the paper-key drill is over a year old
  (`dot secrets audit drilled` records it).
