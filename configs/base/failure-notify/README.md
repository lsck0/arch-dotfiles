# failure-notify

Desktop notifications for what would otherwise sit in the journal:

- a failed user service (`OnFailure=failure-notify@%n.service`; kwalletd6 is skipped, KWallet is disabled here);
- `FAILURES.*` from the last dot run, at login (`failures-login.service`);
- `system-notify`: failed system units, smartd warnings, `dotfiles-health` reports, at most hourly per unit;
- `update-check`, daily: pending updates and fixable security advisories;
- `doctor-check`, hourly: `dot status --brief` into the bar's doctor indicator, notified once per new set;
- `recovery-drill`, monthly with secrets: reminder when the paper-key drill is over a year old
  (`dot secrets audit drilled` records it).
