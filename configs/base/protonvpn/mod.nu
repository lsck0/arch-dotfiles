use module.nu *

export const meta = {packages: {pacman: [proton-vpn-cli]}, volatile: true}

export def link [cfg: record] {
    # without NetworkManager (wsl) nmcli monitor ends at once and Restart= loops
    let wanted = (profile-has secrets) and (which nmcli | is-not-empty)
    [
        (link-commands scripts/auto-vpn.nu)
        (unit-file config/auto-vpn.service)
        (unit-switch auto-vpn.service $wanted --now)
    ]
}
