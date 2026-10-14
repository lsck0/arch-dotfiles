use module.nu *

export const meta = {packages: {pacman: [veracrypt]}}

export def link [cfg: record] {
    # the password prompt needs a terminal, which no apply has
    if not ($nu.home-dir | path join sync vault.hc | path exists) {
        log-info "veracrypt-vault: no container yet; create the 1G one in a terminal with: veracrypt-vault create"
    }
    link-commands veracrypt-vault.nu
}
