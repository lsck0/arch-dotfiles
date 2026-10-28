use module.nu *
use ../fprintd/mod.nu [validity-sensor]

export const meta = {packages: {pacman: [pam-u2f pamtester]}, volatile: true}

export const options = {
    fido_origin: {
        type: string
        # base/yubikey enrolls every key for this origin (its PAM_ORIGIN), so one mapping works on every machine
        default: "pam://lsck0"
        doc: "FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o)"
        label: "U2F origin"
        apply: relink
    }
}

const U2F_MODULE = "/usr/lib/security/pam_u2f.so"
const FPRINT_MODULE = "/usr/lib/security/pam_fprintd.so"
const POLKIT_VENDOR = "/usr/lib/pam.d/polkit-1"
const SUDO = "/etc/pam.d/sudo"
const FPRINT_LINE = "auth       sufficient pam_fprintd.so"
const HUMAN_UIDS = 1000..59999

# u2f against /etc/u2f_mappings, touch only; no nouserok: a user without a key falls through to the password.
def u2f-line [origin: string]: nothing -> string {
    let options = $"cue pinverification=0 authfile=/etc/u2f_mappings origin=($origin) appid=($origin)"
    $"auth       sufficient pam_u2f.so ($options)"
}

# Inserts line before the first system-auth include.
def auth-insert [lines: list<string>, line: string]: nothing -> list<string> {
    let at = $lines | enumerate
        | where {|l| $l.item =~ '^auth\s' and $l.item =~ 'include' and $l.item =~ 'system-auth' }
        | get --optional 0.index
    if $at == null { $lines } else { ($lines | first $at) ++ [$line] ++ ($lines | skip $at) }
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let line = u2f-line $cfg.fido_origin
    let u2f = $U2F_MODULE | path exists
    [
        # copies, pam follows no symlinks
        (file-copy quickshell-lock /etc/pam.d/quickshell-lock)
        (file-render quickshell-lock-u2f /etc/pam.d/quickshell-lock-u2f {ORIGIN: $cfg.fido_origin})
        (step sudo-stack ($u2f | into string) $line)
        # pkexec takes the same factors as sudo: the key, then an enrolled finger, then the password
        (if $u2f and ($POLKIT_VENDOR | path exists) {
            let with_u2f = auth-insert (open --raw $POLKIT_VENDOR | lines) $line
            let lines = if (has-fprint) and ($FPRINT_MODULE | path exists) { auth-insert $with_u2f $FPRINT_LINE } else { $with_u2f }
            file-text /etc/pam.d/polkit-1 ($lines | str join "\n" | $"($in)\n")
        } else { [] })
    ]
}

def has-fprint []: nothing -> bool {
    let unit = ^systemctl list-unit-files --no-legend python3-validity.service | complete | get stdout | str trim
    let validity = ($unit | is-not-empty) and (validity-sensor)
    if $validity { return true }
    if (which fprintd-list | is-empty) { return false }
    open --raw /etc/passwd | lines | parse "{name}:{x}:{uid}:{rest}" | where ($it.uid | into int) in $HUMAN_UIDS
    | any {|u| ^fprintd-list $u.name | complete | get stdout | str contains "Fingerprints for user" }
}

# The yubikey line stays highest, so a changed one also drops the fprintd line, reinserted under it.
export def sudo-stack [u2f: string, line: string]: nothing -> nothing {
    if not ($SUDO | path exists) { return }
    let before = open --raw $SUDO | lines
    let with_u2f = if $u2f != "true" or $line in $before { $before } else {
        auth-insert ($before | where not ($it =~ 'pam_(u2f|fprintd)[.]so')) $line
    }
    let fprint = (has-fprint) and ($FPRINT_MODULE | path exists)
    let after = if $fprint and $FPRINT_LINE not-in $with_u2f {
        auth-insert ($with_u2f | where not ($it =~ 'pam_fprintd[.]so')) $FPRINT_LINE
    } else if not $fprint {
        $with_u2f | where not ($it =~ '^auth\s+sufficient\s+pam_fprintd\.so')
    } else { $with_u2f }
    if $after == $before or not ($after | any { $in =~ system-auth }) { return }
    if not ($"($SUDO).pre-auth.bak" | path exists) { ^cp -a $SUDO $"($SUDO).pre-auth.bak" }
    $after | str join "\n" | $"($in)\n" | save --force $SUDO
}
