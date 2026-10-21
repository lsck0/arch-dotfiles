use module.nu *

export const meta = {packages: {pacman: [proton-vpn-cli]}, volatile: true}

export def link [cfg: record] {
    # without NetworkManager (wsl) nmcli monitor ends at once and Restart= loops
    let wanted = (profile-has secrets) and (which nmcli | is-not-empty)
    [
        (link-commands auto-vpn.nu)
        (unit-file auto-vpn.service)
        (if $wanted { unit-enable auto-vpn.service --now } else { unit-disable auto-vpn.service --now })
    ]
}
