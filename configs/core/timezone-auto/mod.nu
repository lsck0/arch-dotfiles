use module.nu *

const NM_DISPATCHER_DIR = "/etc/NetworkManager/dispatcher.d"
# timezone-auto.nu's and nm-dispatcher.nu's ANY_NETWORK: present, the lookup also runs off a trusted network
const ANY_NETWORK = "/etc/NetworkManager/timezone-auto-any-network"

export const options = {
    any_network: {
        type: bool
        default: false
        doc: ("Look the timezone up on any network, not only a trusted one (base/networkmanager's home or trusted "
            + "gateways), naming this machine's address to ipinfo.io there; a VPN or tor route still skips it")
        label: "Any network"
    }
}

export def link [cfg: record] {
    [
        (unit-file services/timezone-auto.service --values {DIR: $env.PWD})
        (unit-timer timezone-auto.timer "Check the system timezone after boot" --startup 2min
            --accuracy 5min --enable --now)
    ]
}

export def system [cfg: record] {
    [
        (polkit-rules config/49-timezone-auto.rules)
        (if ($NM_DISPATCHER_DIR | path exists) {
            [
                (if $cfg.any_network { file-text $ANY_NETWORK "" })
                (file-copy scripts/nm-dispatcher.nu ($NM_DISPATCHER_DIR | path join 85-timezone-auto) --mode 755)
            ]
        })
    ]
}
