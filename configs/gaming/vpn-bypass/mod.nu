use module.nu *
use games-route.nu [links-physical]

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
        (group-members $GROUP | each {|m| exec $"($GROUP) drops ($m)" [gpasswd -d $m $GROUP] })
        (file-copy games-bypass.nft /etc/nftables.d/games-bypass.nft --then $reload)
        (file-copy games-run.sh /usr/local/bin/games-run --mode 755)
        (file-copy $POLICY ("/usr/share/polkit-1/actions" | path join $POLICY))
        (unit-file $UNIT --enable --then $reload)
        # in name order after home-network and homelab-routes
        (if ("/etc/NetworkManager/dispatcher.d" | path exists) {
            [(file-copy games-route.nu $DISPATCHER --mode 755) (step nudge)]
        })
    ]
}

export def nudge []: nothing -> nothing {
    if (do { ^systemctl is-active -q NetworkManager.service } | complete).exit_code != 0 { return }
    for link in (links-physical) { ^$DISPATCHER $link up }
}
