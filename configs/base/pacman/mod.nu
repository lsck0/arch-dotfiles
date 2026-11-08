use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]
use homelab.nu [LSCK0_SERVER_PLACEHOLDER lsck0-reachable lsck0-drop]

const FILESDB_TIMER = "pacman-filesdb-refresh.timer"
# pacman-contrib's: the install pass runs this verb before and after installing it, the input re-plans it the second time
const FILESDB_TIMER_FILE = $"/usr/lib/systemd/system/($FILESDB_TIMER)"

export const meta = {packages: {pacman: [downgrade pacman-contrib yay]}, inputs: [$FILESDB_TIMER_FILE]}

export const options = {
    yay_cache_days: {
        type: int
        default: 30
        doc: "Days an unused yay build cache dir may sit in $XDG_CACHE_HOME/yay before yay-cache-clean.timer deletes it, find -mtime argument"
        label: "Yay cache retention (days)"
        scope: user
    }
}

const SNAPSHOT = '^(\d{4}-\d{2}-\d{2})?$'

export def system [cfg: record] {
    let snapshot = $env.LSCK0_SNAPSHOT? | default ""
    if not ($snapshot =~ $SNAPSHOT) { error make {msg: $"pacman: lsck0_snapshot '($snapshot)' is not YYYY-MM-DD"} }
    let suffix = if $snapshot == "" { "" } else { $"/($snapshot)" }
    let conf = open --raw pacman.conf | str replace $LSCK0_SERVER_PLACEHOLDER $HOMELAB.mirror.lsck0 | split row "\n" | reduce --fold {out: [], lsck0: false} {|l, acc|
        let lsck0 = if ($l | str starts-with "[") { $l == "[lsck0]" } else { $acc.lsck0 }
        let line = if $lsck0 { $l | str replace --regex '/\$arch$' $"($suffix)/$$arch" } else { $l }
        {out: ($acc.out | append $line), lsck0: $lsck0}
    } | get out | str join "\n"
    # off the lab (no homelab fact) an unreachable [lsck0] would fail every sync: the machine goes on without it and
    # takes it back once it answers; the owner's machines keep it, an outage there is a failure to see
    let conf = if (platform-has homelab) or (lsck0-reachable) { $conf } else {
        print "note: pacman: the homelab mirror does not answer, [lsck0] left out until it does"
        $conf | lsck0-drop
    }
    [
        (step trust)
        (file-text /etc/pacman.conf $conf)
        (files-into /etc/pacman.d/hooks ...(glob hooks/*.hook))
        # pacman -F's database, which names the package of a missing command (cause.nu)
        (if ($FILESDB_TIMER_FILE | path exists) { unit-enable $FILESDB_TIMER --now } else { [] })
        # the weekly timer's first run is up to a week out; until then a fresh install names no package
        (exec filesdb [pacman -Fy] --creates /var/lib/pacman/sync/core.files --network)
    ]
}

# Locally signs archrepo.asc's key, read in a throwaway gpg home so no /root/.gnupg stays behind.
export def trust []: nothing -> nothing {
    let home = mktemp --directory
    let fingerprint = ^gpg --homedir $home --show-keys --with-colons archrepo.asc | lines | parse "fpr:{rest}"
        | get --optional 0.rest | default "" | split row ":" | get --optional 8
    rm --recursive --force $home
    if ($fingerprint | is-empty) { error make {msg: "pacman: no fingerprint in archrepo.asc"} }
    ^pacman-key --add archrepo.asc
    ^pacman-key --lsign-key $fingerprint
}

export def link [cfg: record] {
    [
        (files-into (xdg config pacman) makepkg.conf)
        (file-render yay-cache-clean.service (unit-dir | path join yay-cache-clean.service) {CACHE_DAYS: $cfg.yay_cache_days})
        (unit-file yay-cache-clean.timer --enable --now)
        (shell-aliases pacman)
    ]
}
