use module.nu *

export const meta = {packages: {native: [portmaster-bin]}, volatile: true}

# vm-net's group: its sockets pass portmaster only for DoT to quad9, and it has no members
const VMNET = "vmnet"

export def system [cfg: record] {
    if not ("/var/lib/portmaster" | path exists) { return [] }
    let reload = unit-restart portmaster-bypass.service --reload
    [
        (group-system $VMNET)
        (dropin portmaster.service dotfiles.conf)
        (file-copy config.json /var/lib/portmaster/config.json --then (unit-restart portmaster.service --if-running))
        (file-copy portmaster-bypass.nft /etc/nftables.d/portmaster-bypass.nft --then $reload)
        (unit-file portmaster-bypass.service --enable --then $reload)
        (file-copy vm-net.nu /usr/local/bin/vm-net --mode 755)
        (polkit-rules 49-vm-net.rules)
    ]
}

export def link [cfg: record] {
    if not ("/etc/xdg/autostart/portmaster-autostart.desktop" | path exists) { return [] }
    files-into (xdg config autostart) portmaster-autostart.desktop
}
