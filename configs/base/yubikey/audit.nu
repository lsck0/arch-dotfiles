# `dot secrets audit`: credential ages against their last rotation, plus the recovery drill.

use ../../../scripts/lib/secrets.nu [secret-is-plaintext secrets-wanted]

const SECRETS = path self ../../secrets/keys
const KEY_DIR = path self .
const OWNER_DIR = path self ../../secrets/yubikey
const ROTATION = path self ../../secrets/keys/rotation.txt
const WITNESS = path self ../../secrets/keys/pgp_privatekey.asc
const DRILL = "recovery-drill"
const REMIND_STATE = "secrets-audit/reminded"
const REMIND_EVERY = 28day
const SEALED_HEADER_BYTES = 4096
const CLASSES = [
    [glob class];
    ["wg0.*.conf" wireguard] ["wg0.*.png" -] [ssh_privatekey.asc ssh] [ssh_passphrase ssh]
    ["initramfs-ssh/*/sshkeydir/.ed25519.sk" ssh] ["yubikey/ssh-*" ssh] ["gh/*/token" api] [googleapi api] [sdd_github api] [de-arrow-key api]
    [ntfy-desktop-token api] [trmnl-claude.env api] [calendar.env api] [hermes-anthropic.env api] [protonvpn-netns.conf api] ["taskwarrior-*" api]
    [samba-homelab password] [wifi password] [pgp_privatekey.asc identity]
    [vorrh.private-key.asc identity] [age.txt identity] [age-recovery-key.txt identity] ["syncthing/*/key.pem" identity]
    ["*.pub*" -] ["*_publickey.asc" -] ["*.public-key.asc" -] ["syncthing/*" -] ["initramfs-ssh/*" -] ["borg-*" -]
    ["luks-header-*" -] [rotation.txt -] [home-gateways -] [diablo2/cd-keys -]
    ["claude/*" -] ["caido/*" -] ["modrinth/*" -] ["obs-*.json" -]
]
const MAX_DAYS = {wireguard: 365, api: 365, ssh: 730, password: 730, identity: 1825, recovery-drill: 365}

def finding [level: string, text: string]: nothing -> record { {level: $level, text: $text} }

def secret-class [path: string]: nothing -> string {
    $CLASSES
    | where {|row| $path =~ ('^' + ($row.glob | str replace --all '.' '\.' | str replace --all '*' '.*') + '$') }
    | get --optional 0.class | default ""
}

def rotation-recorded [path: string]: nothing -> string {
    if not ($ROTATION | path exists) { return "" }
    open --raw $ROTATION | lines | split column " " path date | where path == $path
    | get --optional date | last | default ""
}

def rotation-date [path: string]: nothing -> string {
    let recorded = rotation-recorded $path
    if $recorded != "" { return $recorded }
    let committed = ^git -C $SECRETS log -1 --follow --diff-filter=AM --format=%cs -- $path | str trim
    if $committed != "" { return $committed }
    ls ($SECRETS | path join $path) | get 0.modified | format date "%F"
}

def days-since [day: string]: nothing -> int {
    ((date now) - ($day | into datetime --timezone local)) / 1day | math floor
}

def credentials []: nothing -> list<record> {
    let paths = ^git -C $SECRETS ls-files -z --cached --others --exclude-standard | split row "\u{0}" | where $it != ""
    $paths | each {|path|
        let class = secret-class $path
        if $class == "-" { return null }
        if $class == "" {
            return (finding note $"configs/secrets/keys/($path) has no class, add it to CLASSES in configs/base/yubikey/audit.nu")
        }
        let day = rotation-date $path
        let limit = $MAX_DAYS | get $class
        let age = days-since $day
        if $age > $limit {
            let why = $"last rotated ($day), ($age) days ago, limit ($limit)"
            finding fail $"configs/secrets/keys/($path) \(($class)\) ($why); rotate it, then dot secrets audit rotated ($path)"
        } else {
            finding ok $"configs/secrets/keys/($path) \(($class)\) ($day), ($age) of ($limit) days"
        }
    } | compact
}

def recovery []: nothing -> list<record> {
    let host = sys host | get hostname
    let file = $OWNER_DIR | path join recipients.txt
    let recipients = if ($file | path exists) {
        open --raw $file | lines | where ($it | str starts-with age1) | length
    } else { 0 }
    let sealed = $KEY_DIR | path join secrets.key.age
    let stanzas = if ($sealed | path exists) {
        open --raw $sealed | first $SEALED_HEADER_BYTES | decode utf-8 | lines
        | where ($it | str starts-with "-> X25519 ") | length
    } else { 0 }
    let luks = ^lsblk -nro FSTYPE | lines | any { $in == crypto_LUKS }
    let drilled = rotation-recorded $DRILL
    [
        (if $recipients == 0 {
            let file = "configs/secrets/yubikey/recipients.txt"
            finding fail $"($file) holds no paper age recipient, losing every yubikey loses configs/secrets/"
        } else if $stanzas < $recipients {
            let sealed = $"sealed to ($stanzas) of ($recipients) recipients.txt keys"
            finding fail $"secrets.key.age is ($sealed), reseal: dot secrets seal"
        })
        (if $luks and not ($SECRETS | path join $"luks-header-($host).img" | path exists) {
            finding fail $"no configs/secrets/keys/luks-header-($host).img, run configs/base/boot/luks/header-backup.nu"
        })
        (if $drilled == "" {
            finding note 'recovery drill never recorded: RECOVERY.md "Test it", then dot secrets audit drilled'
        } else if (days-since $drilled) > $MAX_DAYS.recovery-drill {
            let how = 'RECOVERY.md "Test it", then dot secrets audit drilled'
            finding note $"recovery drill last done ($drilled), (days-since $drilled) days ago: ($how)"
        } else {
            finding ok $"recovery drill ($drilled), (days-since $drilled) of ($MAX_DAYS.recovery-drill) days"
        })
    ] | compact
}

# Findings {level: ok|note|fail, text}; one note when secrets are not pulled or locked.
export def audit-findings []: nothing -> list<record<level: string, text: string>> {
    if not (secrets-wanted) { return [(finding note "this profile has no secrets capability, nothing audited")] }
    if not (secret-is-plaintext $WITNESS) {
        return [(finding note "configs/secrets/ is locked, nothing audited: dot secrets unlock")]
    }
    (credentials) ++ (recovery)
}

# Prints the findings (--brief: only "fail|note <text>"); exits 1 on a fail.
export def audit-run [--brief]: nothing -> nothing {
    let found = audit-findings
    let shown = if $brief { $found | where level != ok } else { $found }
    let label = if $brief { {fail: "fail ", note: "note "} } else { {fail: "FAIL  ", note: "note  ", ok: "ok    "} }
    $shown | each {|f| $"($label | get $f.level)($f.text)" } | str join "\n" | if $in != "" { print $in }
    if ($found | any { $in.level == fail }) { exit 1 }
}

# Records paths under configs/secrets/keys as rotated today in rotation.txt.
export def audit-rotated [...paths: string]: nothing -> nothing {
    if not (secret-is-plaintext $WITNESS) { error make {msg: "secrets is locked, unlock it first"} }
    if ($paths | is-empty) { error make {msg: "rotated <path under configs/secrets/keys/...>"} }
    let missing = $paths | where {|p| $p != $DRILL and not ($SECRETS | path join $p | path exists) }
    if ($missing | is-not-empty) { error make {msg: $"no configs/secrets/keys/($missing.0)"} }
    let today = date now | format date "%F"
    let kept = if ($ROTATION | path exists) {
        open --raw $ROTATION | lines | where ($it | split row " " | first) not-in $paths
    } else { [] }
    $kept ++ ($paths | each { $"($in) ($today)" }) | sort | str join "\n" | $"($in)\n" | save --force $"($ROTATION).new"
    mv --force $"($ROTATION).new" $ROTATION
    print $"audit: recorded ($paths | str join ' ') on ($today) in configs/secrets/keys/rotation.txt, dot sync commits it"
}

export def audit-drilled []: nothing -> nothing { audit-rotated $DRILL }

# A notification when the recovery drill is due, at most every REMIND_EVERY; unrecorded if none was shown.
export def audit-remind []: nothing -> nothing {
    if not (secret-is-plaintext $WITNESS) { return }
    let drilled = rotation-recorded $DRILL
    if $drilled != "" and (days-since $drilled) <= $MAX_DAYS.recovery-drill { return }
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join $REMIND_STATE
    if ($state | path exists) and (ls $state | get 0.modified) > ((date now) - $REMIND_EVERY) { return }
    let how = 'RECOVERY.md "Test it": unlock a scratch clone with the paper key, then dot secrets audit drilled'
    let body = $"last: ($drilled | default --empty never). ($how)"
    if (do { ^notify-send -a secrets -u normal "Recovery drill due" $body } | complete).exit_code != 0 { return }
    mkdir ($state | path dirname)
    touch $state
}
