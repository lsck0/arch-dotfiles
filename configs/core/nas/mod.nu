use module.nu *

export const meta = {packages: {pacman: [cifs-utils]}, inputs: [/etc/samba/homelab.cred]}

const MOUNT = "/mnt/homelab"
const CRED = "/etc/samba/homelab.cred"
const CRED_KEYS = '^(username|password|domain)='

# the share for every admin of a homelab machine; the credentials are the admin's secret, streamed in as data
export def system [cfg: record] {
    if not (platform-has homelab) { return [] }
    let secret = $env.DOTFILES_SECRETS? | default "" | path join samba-homelab
    if ($secret | path exists) {
        let lines = open --raw $secret | lines | where $it != ""
        if ($lines | any { $in !~ $CRED_KEYS }) or not ($lines | any { str starts-with "password=" }) {
            error make {msg: $"nas: samba-homelab is not a username=/password=/domain= credentials file, keeping ($CRED)"}
        }
    } else if not ($CRED | path exists) {
        # no credentials, no mount: never a guest mount
        log-info "nas: no samba-homelab secret yet, the homelab mount stays off"
        return []
    }
    [
        # installed, not owned: a run without secrets (locked) never takes the credentials away
        (if not ($secret | path exists) or (try { open --raw $CRED } catch { "" }) == (open --raw $secret) { [] } else {
            exec homelab-cred [install -Dm600 -o root -g root $secret $CRED]
        })
        (unit-file mnt-homelab.mount)
        (unit-file mnt-homelab.automount --enable)
    ]
}

# the mount is the machine's; the shortcut only for a homelab user (the sidebar bookmark is base/xdg's)
export def link [cfg: record] {
    if (profile-has homelab) { file-link $MOUNT ($nu.home-dir | path join nas) } else { [] }
}
