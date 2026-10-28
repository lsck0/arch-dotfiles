use module.nu *

const DISPATCHER = "/etc/NetworkManager/dispatcher.d/86-games-route"
const UNIT = "games-bypass.service"

export def system [cfg: record] {
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    # a broken drop-in would break sudo for every admin
    if (^visudo -cf sudoers | complete).exit_code != 0 { error make {msg: "vpn-bypass: sudoers does not validate"} }
    let reload = unit-restart $UNIT --reload
    [
        (group-admins games)
        (file-copy sudoers /etc/sudoers.d/25-games-bypass --mode 440)
        (file-copy games-bypass.nft /etc/nftables.d/games-bypass.nft --then $reload)
        (unit-file $UNIT --enable --then $reload)
        # in name order after home-network and homelab-routes
        (if ("/etc/NetworkManager/dispatcher.d" | path exists) {
            [(file-copy games-route.nu $DISPATCHER --mode 755) (step nudge)]
        } else { [] })
    ]
}

export def nudge []: nothing -> nothing {
    if (do { ^systemctl is-active -q NetworkManager.service } | complete).exit_code != 0 { return }
    let links = ^nmcli -t -f DEVICE,TYPE,STATE device | lines | split column ":" dev type state
        | where state == connected and type in [ethernet wifi] and ($"/sys/class/net/($it.dev)/device" | path exists)
    for l in $links { ^$DISPATCHER $l.dev up }
}
