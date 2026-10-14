use module.nu *

export const meta = {packages: {pacman: [qbittorrent]}}

# proton0 down leaves qbittorrent bound to a missing interface, stalled instead of leaking
const VPN_INTERFACE = "proton0"

# Interface is what the session binds, InterfaceName only the gui's label; qbittorrent rewrites its config on exit
export def link [cfg: record] {
    let file = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join qBittorrent qBittorrent.conf
    [
        (ini-merge $file {BitTorrent: {'Session\Interface': $VPN_INTERFACE, 'Session\InterfaceName': $VPN_INTERFACE, 'Session\InterfaceAddress': ""}})
        # seeded once, so a later change in qbittorrent sticks
        (ini-merge $file --missing-only {
            LegalNotice: {Accepted: "true"}
            BitTorrent: {'Session\Encryption': "0"}
            Preferences: {'Advanced\AnnounceToAllTrackers': "true", 'Advanced\updateCheck': "false"}
        })
    ]
}
