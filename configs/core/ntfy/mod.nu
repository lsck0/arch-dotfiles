use module.nu *

const TOKEN = "secrets/ntfy-desktop-token"
const HOMELAB_URL = "https://github.com/lsck0/homelab.git"

export def link [cfg: record] {
    if not (profile-has homelab) or (which notify-send | is-empty) { return [] }
    if not (secret-is-plaintext ($env.DOTFILES | path join $TOKEN)) {
        log-warn $"ntfy: no readable ($TOKEN), no forwarder"
        return []
    }
    # programming/projects may clone the homelab at the same time: the losing clone must not fail
    let homelab = $nu.home-dir | path join projects homelab
    [
        (exec homelab-clone [sh -c $"git clone --recurse-submodules ($HOMELAB_URL) ($homelab) || true"] --creates ($homelab | path join .git))
        (file-render ntfy-notify.service (unit-dir | path join ntfy-notify.service) {DIR: $env.PWD})
        (unit-enable ntfy-notify.service --now)
    ]
}
