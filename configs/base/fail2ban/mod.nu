use module.nu *

export const meta = {packages: {native: [fail2ban]}}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        # a restart, not a reload: 1.1.1's reload drops a changed banaction
        (file-copy jail.local /etc/fail2ban/jail.local --then [systemctl restart fail2ban.service])
        (unit-enable fail2ban.service --now)
    ]
}
