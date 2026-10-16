use module.nu *

const TOKEN = "secrets/ntfy-desktop-token"
const HOMELAB_URL = "https://github.com/lsck0/homelab.git"

# the homelab ntfy denies anonymous reads: no homelab user, notifier or token, no forwarder
export def link [cfg: record] {
    if not (profile-has homelab) or (which notify-send | is-empty) { return [] }
    if not (secret-is-plaintext ($env.DOTFILES | path join $TOKEN)) {
        log-warn $"ntfy: no readable ($TOKEN), no forwarder"
        return []
    }
    # the topics come from the homelab checkout; programming/projects clones it too, on machines that have it, and
    # both jobs can run concurrently: `--creates` only guards at plan time, so a losing clone into the same dir
    # must tolerate "already exists" rather than fail the whole module (the winner still finishes the real clone)
    let homelab = $nu.home-dir | path join projects homelab
    [
        (exec homelab-clone [sh -c $"git clone --recurse-submodules ($HOMELAB_URL) ($homelab) || true"] --creates ($homelab | path join .git))
        (file-render ntfy-notify.service (unit-dir | path join ntfy-notify.service) {DIR: $env.PWD})
        (unit-enable ntfy-notify.service --now)
    ]
}
