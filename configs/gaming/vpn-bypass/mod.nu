use module.nu *

const DISPATCHER = "/etc/NetworkManager/dispatcher.d/85-games-route"
const UNIT = "games-bypass.service"
const RELOAD = [systemctl reload-or-restart games-bypass.service]

# the games group's traffic around proton0 on the real link, fail safe: a game leaves the tunnel, nothing else does, and
# a missing piece leaves the game on the vpn. the group (steam-launch enters it through sudoers), table inet
# games_bypass marking its sockets, and an NM dispatcher keeping table 100 and a fwmark rule on the physical gateway;
# the kill switch lets the mark out in configs/base/nftables/fw-egress.nft
export def system [cfg: record] {
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    # a broken drop-in would break sudo for every admin
    if (^visudo -cf sudoers | complete).exit_code != 0 { error make {msg: "vpn-bypass: sudoers does not validate"} }
    [
        (group-admins games)
        (file-copy sudoers /etc/sudoers.d/25-games-bypass --mode 440)
        (file-copy games-bypass.nft /etc/nftables.d/games-bypass.nft --then $RELOAD)
        (unit-file $UNIT --enable --then $RELOAD)
        # NM owns this only where it is present (not in a bare vm); runs in name order after home-network and
        # homelab-routes
        (if ("/etc/NetworkManager/dispatcher.d" | path exists) {
            [(file-copy games-route.nu $DISPATCHER --mode 755) (step nudge)]
        } else { [] })
    ]
}

# the dispatcher fires on the next network change; the live physical links get the rule and table now
export def nudge []: nothing -> nothing {
    let links = ^nmcli -t -f DEVICE,TYPE,STATE device | lines | split column ":" dev type state
        | where state == connected and type in [ethernet wifi] and ($"/sys/class/net/($it.dev)/device" | path exists)
    for l in $links { ^$DISPATCHER $l.dev up }
}
