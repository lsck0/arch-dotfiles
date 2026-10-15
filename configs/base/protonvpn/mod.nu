use module.nu *

export const meta = {packages: {pacman: [proton-vpn-cli]}, volatile: true}

# only an identity has a proton account; without NetworkManager (wsl) nmcli monitor ends at once and Restart= loops
export def link [cfg: record] {
    let wanted = (profile-has identity) and (which nmcli | is-not-empty)
    [
        (link-commands auto-vpn.nu)
        (unit-file auto-vpn.service)
        (if $wanted { unit-enable auto-vpn.service --now } else { unit-disable auto-vpn.service --now })
    ]
}
