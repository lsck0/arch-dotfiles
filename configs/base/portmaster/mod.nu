use module.nu *

export const meta = {packages: {native: [portmaster-bin]}, volatile: true}

# global rules only, its config file has no per-app ones
export def system [cfg: record] {
    if not ("/var/lib/portmaster" | path exists) { return [] }
    let reload = unit-restart portmaster-bypass.service --reload
    [
        (dropin portmaster.service dotfiles.conf)
        # a copy: ProtectHome=read-only
        (file-copy config.json /var/lib/portmaster/config.json --then [systemctl try-restart portmaster.service])
        # loopback, pentest vpns, the pentest group and system vms skip its per-connection queue
        (file-copy portmaster-bypass.nft /etc/nftables.d/portmaster-bypass.nft --then $reload)
        (unit-file portmaster-bypass.service --enable --then $reload)
    ]
}

export def link [cfg: record] {
    if not ("/etc/xdg/autostart/portmaster-autostart.desktop" | path exists) { return [] }
    let autostart = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join autostart
    files-into $autostart portmaster-autostart.desktop
}
