use module.nu *

export const meta = {packages: {pacman: [qbittorrent]}}

# torrent traffic flows only through the protonvpn tunnel: while proton0 is down qbittorrent binds a missing interface
# and stalls instead of leaking, a per-app killswitch independent of the routing and firewall toggles
const VPN_INTERFACE = "proton0"

# qbittorrent rewrites its config on exit, so the binding is forced each run; Interface is what the session binds,
# InterfaceName only the gui's label (without Interface it listens on every nic), an empty address any on it
export def link [cfg: record] {
    let file = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join qBittorrent qBittorrent.conf
    [
        (ini-merge $file {BitTorrent: {'Session\Interface': $VPN_INTERFACE, 'Session\InterfaceName': $VPN_INTERFACE, 'Session\InterfaceAddress': ""}})
        # seeded once, a later change in qbittorrent sticks: no eula dialog, prefer encrypted peers, no update check
        (ini-merge $file --missing-only {
            LegalNotice: {Accepted: "true"}
            BitTorrent: {'Session\Encryption': "0"}
            Preferences: {'Advanced\AnnounceToAllTrackers': "true", 'Advanced\updateCheck': "false"}
        })
    ]
}
