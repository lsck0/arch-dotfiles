use module.nu *

export const meta = {packages: {pacman: [veracrypt]}}

export def link [cfg: record] {
    if not ($nu.home-dir | path join sync vault.hc | path exists) {
        log-note "veracrypt-vault: no container yet; create one in a terminal with: veracrypt-vault create [size]"
    }
    link-commands veracrypt-vault.nu
}
