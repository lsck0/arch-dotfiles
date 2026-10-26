use module.nu *

export const meta = {packages: {pacman: [qbittorrent]}}

const VPN_INTERFACE = "proton0"

export def link [cfg: record] {
    let file = xdg config qBittorrent qBittorrent.conf
    [
        (ini-merge $file {BitTorrent: {'Session\Interface': $VPN_INTERFACE, 'Session\InterfaceName': $VPN_INTERFACE, 'Session\InterfaceAddress': ""}})
        (ini-merge $file --missing-only {
            LegalNotice: {Accepted: "true"}
            BitTorrent: {'Session\Encryption': "0"}
            Preferences: {'Advanced\AnnounceToAllTrackers': "true", 'Advanced\updateCheck': "false"}
        })
    ]
}
