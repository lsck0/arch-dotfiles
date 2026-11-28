use module.nu *
use system.nu [ENTRY]
use ../fprintd/mod.nu [validity-sensor-ids]

export const meta = {packages: {pacman: [pam-u2f pamtester]}, volatile: true}

export const options = {
    fido_origin: {
        type: string
        # base/yubikey enrolls every key for this origin (its PAM_ORIGIN), so one mapping works on every machine
        default: "pam://lsck0"
        doc: "FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o)"
        label: "U2F origin"
    }
}

const U2F_MODULE = "/usr/lib/security/pam_u2f.so"
const FPRINT_MODULE = "/usr/lib/security/pam_fprintd.so"
const POLKIT_VENDOR = "/usr/lib/pam.d/polkit-1"
const SUDO = "/etc/pam.d/sudo"
const SYSTEM_AUTH = "/etc/pam.d/system-auth"
# pambase's lines for systemd-homed, each a D-Bus activation of org.freedesktop.home1 that fails where homed is off
const HOMED_LINE = 'pam_systemd_home[.]so'
const SYSTEM_POLICY = "dev.lsck0.dotfiles.system.policy"
const POLKIT_ACTIONS = "/usr/share/polkit-1/actions"
const FPRINT_LINE = "auth       sufficient pam_fprintd.so"
# sudo sets PAM_TTY to its terminal or to "": without one, no factor is tried, so a process with no terminal (an
# agent's tool shell) can neither raise a key or finger request nobody sees nor pipe a password in. Any pty passes: a
# process that allocates one (script, a multiplexer pane) is not held back here
const TTY_LINE = "auth       requisite  pam_succeed_if.so quiet_success tty =~ ?*"
# the uids of human logins; desktop/ly reads its users from the same range
export const HUMAN_UIDS = 1000..59999
const SYSTEM_AUTH_INCLUDE = '^auth\s.*include.*system-auth'
const AUTH_ANY = '^-?auth\s'

# u2f against /etc/u2f_mappings, touch only; no nouserok: a user without a key falls through to the password.
export def u2f-line [origin: string]: nothing -> string {
    let options = $"cue pinverification=0 authfile=/etc/u2f_mappings origin=($origin) appid=($origin)"
    $"auth       sufficient pam_u2f.so ($options)"
}

# Inserts line before the first line matching before, by default the first system-auth include.
def auth-insert [lines: list<string>, line: string, before: string = $SYSTEM_AUTH_INCLUDE]: nothing -> list<string> {
    let at = $lines | enumerate | where {|l| $l.item =~ $before } | get --optional 0.index
    if $at == null { $lines } else { ($lines | first $at) ++ [$line] ++ ($lines | skip $at) }
}

export def system [cfg: record] {
    # WSLg is graphical too, so dot's root-runner can pick pkexec there
    let entry = $SYSTEM_REPO | path join $ENTRY
    let policy = file-render $"config/($SYSTEM_POLICY)" ($POLKIT_ACTIONS | path join $SYSTEM_POLICY) {ENTRY: $entry}
    if $env.FORM_FACTOR? == "wsl" { return [$policy] }
    let line = u2f-line $cfg.fido_origin
    let u2f = $U2F_MODULE | path exists
    let homed = (^systemctl is-enabled systemd-homed.service | complete | get stdout | str trim) == "enabled"
    [
        $policy
        # copies, pam follows no symlinks
        (file-copy config/quickshell-lock /etc/pam.d/quickshell-lock)
        (file-render config/quickshell-lock-u2f /etc/pam.d/quickshell-lock-u2f {ORIGIN: $cfg.fido_origin})
        # the lock screen offers the finger only where this service exists
        (if (has-fprint) { file-copy config/quickshell-lock-fprint /etc/pam.d/quickshell-lock-fprint })
        (file-copy config/faillock.conf /etc/security/faillock.conf)
        (step sudo-stack ($u2f | into string) $line)
        (step system-auth-homed ($homed | into string))
        # pkexec takes the same factors as sudo: the key, then an enrolled finger, then the password
        (if $u2f and ($POLKIT_VENDOR | path exists) {
            let with_u2f = auth-insert (open --raw $POLKIT_VENDOR | lines) $line
            let lines = if (has-fprint) { auth-insert $with_u2f $FPRINT_LINE } else { $with_u2f }
            file-text /etc/pam.d/polkit-1 ($lines | to text)
        })
    ]
}

# Whether pam_fprintd can take a finger: a validity sensor, or a login with one enrolled.
def has-fprint []: nothing -> bool {
    if not ($FPRINT_MODULE | path exists) { return false }
    if (unit-installed python3-validity.service) and (validity-sensor-ids | is-not-empty) { return true }
    if (which fprintd-list | is-empty) { return false }
    open --raw /etc/passwd | lines | parse "{name}:{x}:{uid}:{rest}" | where ($it.uid | into int) in $HUMAN_UIDS
    | any {|u| ^fprintd-list $u.name | complete | get stdout | str contains "Fingerprints for user" }
}

# Without homed, every login, sudo and polkit check asks D-Bus for it and the bus logs "Activation request for
# 'org.freedesktop.home1' failed": its lines go. Enabling homed puts the stock file back from the backup.
export def system-auth-homed [homed: string]: nothing -> nothing {
    let backup = $"($SYSTEM_AUTH).pre-homed.bak"
    if $homed == "true" {
        if ($backup | path exists) { ^mv -f $backup $SYSTEM_AUTH }
        return
    }
    if not ($SYSTEM_AUTH | path exists) { return }
    let before = open --raw $SYSTEM_AUTH | lines
    let after = system-auth-lines $before
    if $after == $before {
        if ($before | any { $in =~ $HOMED_LINE }) {
            print $"note: pam: a jump in ($SYSTEM_AUTH) crosses a homed line, left as it is"
        }
        return
    }
    if not ($backup | path exists) { ^cp -a $SYSTEM_AUTH $backup }
    $after | to text | save --force $SYSTEM_AUTH
}

# system-auth without homed's lines. A jump (success=n) over one would land on another line once it is gone, which
# could skip the password, so a stack with such a jump stays as it is.
export def system-auth-lines [before: list<string>]: nothing -> list<string> {
    let rules = $before | enumerate | where {|l| $l.item =~ '^-?[a-z]+\s' } | each {|l|
        let jump = $l.item | parse --regex 'success=(?<n>\d+)' | get --optional 0.n
        let type = $l.item | parse --regex '^-?(?<t>[a-z]+)' | get 0.t
        {at: $l.index, type: $type, homed: ($l.item =~ $HOMED_LINE), jump: $jump}
    }
    let crossed = $rules | where {|r| not $r.homed and $r.jump != null } | any {|r|
        $rules | where {|o| $o.type == $r.type and $o.at > $r.at } | first ($r.jump | into int) | any { $in.homed }
    }
    if $crossed { $before } else { $before | where not ($it =~ $HOMED_LINE) }
}

# The terminal gate first, then the yubikey line, so a changed one also drops the fprintd line, reinserted under it.
export def sudo-stack [u2f: string, line: string]: nothing -> nothing {
    if not ($SUDO | path exists) { return }
    let before = open --raw $SUDO | lines
    let after = sudo-lines $before ($u2f == "true") $line (has-fprint)
    if $after == $before or not ($after | any { $in =~ system-auth }) { return }
    if not ($"($SUDO).pre-auth.bak" | path exists) { ^cp -a $SUDO $"($SUDO).pre-auth.bak" }
    $after | to text | save --force $SUDO
}

# sudo's stack with the factors in: the terminal gate, the u2f line, the fprintd line where a finger can be taken, then
# the stock system-auth include (the password).
export def sudo-lines [before: list<string>, u2f: bool, line: string, fprint: bool]: nothing -> list<string> {
    let with_u2f = if not $u2f or $line in $before { $before } else {
        auth-insert ($before | where not ($it =~ 'pam_(u2f|fprintd)[.]so')) $line
    }
    let after = if $fprint and $FPRINT_LINE not-in $with_u2f {
        auth-insert ($with_u2f | where not ($it =~ 'pam_fprintd[.]so')) $FPRINT_LINE
    } else if not $fprint {
        $with_u2f | where not ($it =~ '^auth\s+sufficient\s+pam_fprintd\.so')
    } else { $with_u2f }
    auth-insert ($after | where $it != $TTY_LINE) $TTY_LINE $AUTH_ANY
}
