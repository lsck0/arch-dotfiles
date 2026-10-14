use module.nu *

export const meta = {packages: {pacman: [pam-u2f pamtester]}, volatile: true}

export const options = {
    fido_origin: {
        type: string?
        default: null
        doc: "FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o); null: pam://<hostname>"
        label: "U2F origin"
        apply: relink
        scope: machine
    }
}

const U2F_MODULE = "/usr/lib/security/pam_u2f.so"
const FPRINT_MODULE = "/usr/lib/security/pam_fprintd.so"
# root's copy of every enrolled key, one user:key... line per user
const U2F_KEYS = "../yubikey/u2f_keys"
# polkit ships its stack in /usr/lib/pam.d, an /etc one of the same name replaces it
const POLKIT_VENDOR = "/usr/lib/pam.d/polkit-1"
const SUDO = "/etc/pam.d/sudo"
const FPRINT_LINE = "auth       sufficient pam_fprintd.so"
# login.defs' range for people: the users whose enrolled fingers count
const HUMAN_UIDS = 1000..59999

export def detect [cfg: record]: nothing -> record {
    {fido_origin: $"pam://(open --raw /etc/hostname | str trim)"}
}

# one root-owned mapping, never the user's own u2f_keys a process of theirs could add a key to. the fido2 pin plus
# touch: a bare touch is no second factor against a process of the session. no nouserok: a user without a key falls
# through to the password include
def u2f-line [origin: string]: nothing -> string {
    let options = $"cue pinverification=1 authfile=/etc/u2f_mappings origin=($origin) appid=($origin)"
    $"auth       sufficient pam_u2f.so ($options)"
}

# before the first system-auth include
def auth-insert [lines: list<string>, line: string]: nothing -> list<string> {
    let at = $lines | enumerate
        | where {|l| $l.item =~ '^auth\s' and $l.item =~ 'include' and $l.item =~ 'system-auth' }
        | get --optional 0.index
    if $at == null { $lines } else { ($lines | first $at) ++ [$line] ++ ($lines | skip $at) }
}

# fingerprint and yubikey on sudo, the yubikey on polkit prompts, additive to the password; login takes the password
# only. the lock screen keeps them apart: a password service and a pin+touch one, so a password never reaches the key
export def system [cfg: record] {
    # windows owns sign-in hardware under wsl
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let line = u2f-line $cfg.fido_origin
    let u2f = $U2F_MODULE | path exists
    [
        # copies, pam follows no symlinks
        (file-copy quickshell-lock /etc/pam.d/quickshell-lock)
        (file-render quickshell-lock-u2f /etc/pam.d/quickshell-lock-u2f {ORIGIN: $cfg.fido_origin})
        (if ($U2F_KEYS | path exists) { file-copy $U2F_KEYS /etc/u2f_mappings } else { [] })
        (step sudo-stack ($u2f | into string) $line)
        # rebuilt from the vendor stack, so a polkit update reaches it; pam-u2f's polkit-agent-helper@ drop-in lets the
        # sandboxed helper open the key
        (if $u2f and ($POLKIT_VENDOR | path exists) {
            let text = auth-insert (open --raw $POLKIT_VENDOR | lines) $line | str join "\n" | $"($in)\n"
            file-text /etc/pam.d/polkit-1 $text
        } else { [] })
    ]
}

# a validity/synaptics sensor uses python-validity + open-fprintd, other readers fprintd once anyone enrolled a finger
def has-fprint []: nothing -> bool {
    let unit = ^systemctl list-unit-files --no-legend python3-validity.service | complete | get stdout | str trim
    let validity = ($unit | is-not-empty) and ([138a: 06cb:] | any {|id| (^lsusb -d $id | complete).exit_code == 0 })
    if $validity { return true }
    if (which fprintd-list | is-empty) { return false }
    open --raw /etc/passwd | lines | parse "{name}:{x}:{uid}:{rest}" | where ($it.uid | into int) in $HUMAN_UIDS
    | any {|u| ^fprintd-list $u.name | complete | get stdout | str contains "Fingerprints for user" }
}

# the yubikey line stays highest (the habit), so a changed one also drops the fprintd line, reinserted under it
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
