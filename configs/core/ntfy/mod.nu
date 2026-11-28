use module.nu *

export const meta = {inputs: [/usr/bin/notify-send]}

const TOKEN = "configs/secrets/keys/ntfy-desktop-token"
const HOMELAB_URL = "https://github.com/lsck0/homelab.git"

export def link [cfg: record] {
    if not (owner-unlocked) or not (platform-has homelab) or (which notify-send | is-empty) { return [] }
    if not (secret-is-plaintext ($env.DOTFILES | path join $TOKEN)) {
        log-warn $"ntfy: no readable ($TOKEN), the forwarder idles until the secrets are unlocked"
    }
    let homelab = $nu.home-dir | path join projects homelab
    [
        # programming/projects may clone the homelab at the same time: the losing clone passes on the winner's checkout
        (exec homelab-clone [sh -c $"git clone --recurse-submodules ($HOMELAB_URL) ($homelab) || test -d ($homelab)/.git"]
            --creates ($homelab | path join .git) --network)
        (unit-file services/ntfy-notify.service --values {DIR: $env.PWD} --enable --now)
    ]
}
