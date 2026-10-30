use module.nu *

# volatile: the homelab mirror is added only when it answers, so a run away from home retries on the next apply
export const meta = {packages: {pacman: [ghostmirror]}, volatile: true}

export const options = {
    homelab_mirror: {
        type: string?
        default: null
        doc: "A homelab pacman mirror's URL ($repo and $arch as in a mirrorlist), put first on a homelab machine"
    }
}

const MIRRORLIST = "/etc/pacman.d/mirrorlist"
const HOMELAB_FILE = "/etc/pacman.d/homelab-mirror"
const UPDATE_TIMEOUT_S = 600

export def system [cfg: record] {
    let homelab = if (platform-has homelab) and $cfg.homelab_mirror != null { $"Server=($cfg.homelab_mirror)" }
    [
        (file-copy mirrorlist-update.nu /usr/local/bin/mirrorlist-update --mode 755)
        (if $homelab != null { file-text $HOMELAB_FILE $"($homelab)\n" } else { [] })
        (step place ($homelab | default ""))
        (unit-file ghostmirror.service)
        (unit-file ghostmirror.timer --enable --now)
        (unit-file ghostmirror-refresh.service)
        (unit-file ghostmirror-refresh.timer --enable --now)
    ]
}

def mirrorlist-swap [lines: list<string>]: nothing -> nothing {
    $lines | str join "\n" | $"($in)\n" | save --force $"($MIRRORLIST).new"
    ^mv -f $"($MIRRORLIST).new" $MIRRORLIST
}

def update [mode: string, ...args: string]: nothing -> bool {
    (^timeout $UPDATE_TIMEOUT_S /usr/local/bin/mirrorlist-update $mode ...$args | complete).exit_code == 0
}

# homelab is the wanted Server line or empty, read from the argument: HOMELAB_FILE may be stale until the orphan
# removal after this step.
export def place [homelab: string]: nothing -> nothing {
    let linked = ($MIRRORLIST | path type) == "symlink"
    if $linked or not (open --raw $MIRRORLIST | lines | any { str starts-with "# lastsync" }) {
        if (update rebuild) {
            update sort | ignore
        } else if $linked or not (open --raw $MIRRORLIST | lines | any { str starts-with "Server" }) {
            mirrorlist-swap (open --raw mirrorlist | lines)
        }
    }
    update homelab $homelab | ignore
}
