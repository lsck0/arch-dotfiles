use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

const MOUNT = "/mnt/homelab"
const CRED = "/etc/samba/homelab.cred"
const CRED_KEYS = '^(username|password|domain)='

export const meta = {packages: {pacman: [cifs-utils]}, inputs: [$CRED], secrets: [samba-homelab]}

export const options = {
    share: {
        type: string
        default: $HOMELAB.nas.smb
        doc: "The homelab NAS's smb share mounted at /mnt/homelab (//host/share)"
    }
}

export def system [cfg: record] {
    if not (platform-has homelab) { return [] }
    let secret = system-secret samba-homelab
    let present = $secret | path exists
    if $present {
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
        (if $present and (try { open --raw $CRED } catch { "" }) != (open --raw $secret) {
            exec homelab-cred [install -Dm600 -o root -g root $secret $CRED]
        })
        (file-render mnt-homelab.mount (unit-dir | path join mnt-homelab.mount) {SHARE: $cfg.share})
        (unit-file mnt-homelab.automount --enable)
    ]
}

export def link [cfg: record] {
    if (owner-unlocked) and (platform-has homelab) { file-link $MOUNT ($nu.home-dir | path join nas) }
}
