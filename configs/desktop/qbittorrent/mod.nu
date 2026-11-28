use module.nu *

export const meta = {packages: {pacman: [qbittorrent]}}

export const options = {
    interface: {
        type: string?
        default: null
        doc: "Interface qBittorrent is bound to; empty, none; unset, proton/vpn's proton0 where the profile has secrets"
        label: "Bound interface"
    }
}

# core/proton/vpn's tunnel, which only a profile with the secrets capability brings up
const VPN_INTERFACE = "proton0"

export def link [cfg: record] {
    let file = xdg config qBittorrent qBittorrent.conf
    # declared even when empty, qBittorrent's any interface: the ini merge keeps no record to undo a dropped key
    let interface = $cfg.interface | default (if (profile-has secrets) { $VPN_INTERFACE } else { "" })
    [
        (ini-merge $file {BitTorrent: {'Session\Interface': $interface, 'Session\InterfaceName': $interface, 'Session\InterfaceAddress': ""}})
        (ini-merge $file --missing-only {
            LegalNotice: {Accepted: "true"}
            BitTorrent: {'Session\Encryption': "0"}
            Preferences: {'Advanced\AnnounceToAllTrackers': "true", 'Advanced\updateCheck': "false"}
        })
    ]
}
