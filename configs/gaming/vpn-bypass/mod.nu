use module.nu *
use scripts/games-route.nu [links-physical]

const DISPATCHER = "/etc/NetworkManager/dispatcher.d/86-games-route"
const UNIT = "games-bypass.service"
const GROUP = "vpn-bypass"
const POLICY = "dev.lsck0.vpn-bypass.policy"

export def system [cfg: record] {
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let reload = unit-restart $UNIT --reload
    [
        (group-system $GROUP)
        # no members: newgrp would hand a member the bypass without asking; games-run asks for the key
        (group-members-remove $GROUP)
        (file-copy config/games-bypass.nft /etc/nftables.d/games-bypass.nft --then $reload)
        (file-copy scripts/games-run.sh /usr/local/bin/games-run --mode 755)
        (file-copy ("config" | path join $POLICY) ("/usr/share/polkit-1/actions" | path join $POLICY))
        (unit-file ("services" | path join $UNIT) --enable --then $reload)
        # in name order after home-network and homelab-routes
        (if ("/etc/NetworkManager/dispatcher.d" | path exists) {
            [(file-copy scripts/games-route.nu $DISPATCHER --mode 755) (step nudge)]
        })
    ]
}

export def nudge []: nothing -> nothing {
    if not (unit-active NetworkManager.service) { return }
    for link in (links-physical) { ^$DISPATCHER $link up }
}
