use module.nu *

export const meta = {packages: {native: [fail2ban]}}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        # 1.1.1's reload drops a changed banaction instead of swapping it; bans persist in its db.
        # the config first: a restart right after --now ran ExecStop before the server's socket was up
        (file-copy jail.local /etc/fail2ban/jail.local --then [systemctl restart fail2ban.service])
        (unit-enable fail2ban.service --now)
    ]
}
