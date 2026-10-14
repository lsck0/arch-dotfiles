use module.nu *

export const meta = {packages: {pacman: [borg]}}

# the repo is a syncthing folder only a homelab user's nas receives, so only a homelab user backs up
export def link [cfg: record] {
    if not (profile-has homelab) { return [] }
    if not (secret-is-plaintext ($env.DOTFILES | path join secrets borg-passphrase)) {
        log-warn "borg: no readable secrets/borg-passphrase, every run fails until there is one (README.md)"
    }
    [
        (link-commands borg-backup.nu)
        (unit-file borg-backup.service)
        (unit-file borg-backup.timer --enable)
    ]
}
