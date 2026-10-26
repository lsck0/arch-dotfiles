use module.nu *

export const meta = {packages: {native: [fail2ban]}}

export const options = {
    bantime: {
        type: int
        default: 3600
        doc: "Seconds an IP stays banned after too many failed attempts, fail2ban jail.conf(5) bantime"
        label: "Ban duration (s)"
    }
    findtime: {
        type: int
        default: 600
        doc: "Seconds of history fail2ban scans for failed attempts, fail2ban jail.conf(5) findtime"
        label: "Lookback window (s)"
    }
    maxretry: {
        type: int
        default: 5
        doc: "Failed attempts within findtime before an IP is banned, fail2ban jail.conf(5) maxretry"
        label: "Max retries before ban"
    }
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        # a restart, not a reload: 1.1.1's reload drops a changed banaction
        (file-render jail.local /etc/fail2ban/jail.local {BANTIME: $cfg.bantime, FINDTIME: $cfg.findtime, MAXRETRY: $cfg.maxretry}
            --then [systemctl restart fail2ban.service])
        (unit-enable fail2ban.service --now)
    ]
}
