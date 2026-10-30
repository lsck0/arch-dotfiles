use module.nu *

export const meta = {packages: {pacman: [cifs-utils]}, inputs: [/etc/samba/homelab.cred]}

const MOUNT = "/mnt/homelab"
const CRED = "/etc/samba/homelab.cred"
const CRED_KEYS = '^(username|password|domain)='

export def system [cfg: record] {
    if not (platform-has homelab) { return [] }
    let secrets = $env.DOTFILES_SECRETS? | default ""
    let secret = if $secrets == "" { null } else { $secrets | path join samba-homelab }
    if $secret != null and ($secret | path exists) {
        let lines = open --raw $secret | lines | where $it != ""
        if ($lines | any { $in !~ $CRED_KEYS }) or not ($lines | any { str starts-with "password=" }) {
            error make {msg: $"nas: samba-homelab is not a username=/password=/domain= credentials file, keeping ($CRED)"}
        }
    } else if not ($CRED | path exists) {
        log-info "nas: no samba-homelab secret yet, the homelab mount stays off"
        return []
    }
    [
        # installed, not owned: a run with locked secrets never takes the credentials away
        (if $secret == null or not ($secret | path exists) or (try { open --raw $CRED } catch { "" }) == (open --raw $secret) { [] } else {
            exec homelab-cred [install -Dm600 -o root -g root $secret $CRED]
        })
        (unit-file mnt-homelab.mount)
        (unit-file mnt-homelab.automount --enable)
    ]
}

export def link [cfg: record] {
    if (owner-unlocked) and (platform-has homelab) { file-link $MOUNT ($nu.home-dir | path join nas) } else { [] }
}
