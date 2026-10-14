use module.nu *

export const meta = {packages: {native: [portmaster-bin]}}

const BYPASS_RELOAD = [systemctl reload-or-restart portmaster-bypass.service]

# global rules only, its config file has no per-app ones: mdns (avahi) both ways and ipp/ipps (cupsd) out, lan only;
# lists: its defaults plus ADS, UNBREAK carries its exceptions for what the other lists break
export def system [cfg: record] {
    if not ("/var/lib/portmaster" | path exists) { return [] }
    [
        (dropin portmaster.service dotfiles.conf)
        # a copy: ProtectHome=read-only; read at start only, and stays stopped while a toggle holds it off
        (file-copy config.json /var/lib/portmaster/config.json --then [systemctl try-restart portmaster.service])
        # loopback, pentest vpns, the pentest group and system vms skip its per-connection queue
        (file-copy portmaster-bypass.nft /etc/nftables.d/portmaster-bypass.nft --then $BYPASS_RELOAD)
        (unit-file portmaster-bypass.service --enable --then $BYPASS_RELOAD)
    ]
}

export def link [cfg: record] {
    if not ("/etc/xdg/autostart/portmaster-autostart.desktop" | path exists) { return [] }
    let autostart = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join autostart
    files-into $autostart portmaster-autostart.desktop
}
