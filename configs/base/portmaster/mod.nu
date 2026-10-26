use module.nu *

export const meta = {packages: {native: [portmaster-bin]}, volatile: true}

export def system [cfg: record] {
    if not ("/var/lib/portmaster" | path exists) { return [] }
    let reload = unit-restart portmaster-bypass.service --reload
    [
        (dropin portmaster.service dotfiles.conf)
        (file-copy config.json /var/lib/portmaster/config.json --then [systemctl try-restart portmaster.service])
        (file-copy portmaster-bypass.nft /etc/nftables.d/portmaster-bypass.nft --then $reload)
        (unit-file portmaster-bypass.service --enable --then $reload)
    ]
}

export def link [cfg: record] {
    if not ("/etc/xdg/autostart/portmaster-autostart.desktop" | path exists) { return [] }
    let autostart = xdg config autostart
    files-into $autostart portmaster-autostart.desktop
}
