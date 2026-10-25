#!/usr/bin/env -S nu --no-config-file
# aa: per-machine apparmor modes (flags.d/include.d manual.conf), layered over the dotfiles baseline

const REPO = path self | path expand | path dirname | path join ../../.. | path expand
use ($REPO | path join scripts lib usage.nu) [die]

const INCLUDE = "/etc/apparmor/include.d/manual.conf"
const FLAGS = "/etc/apparmor/flags.d/manual.conf"
const BASELINE_FLAGS = "/etc/apparmor/flags.d/dotfiles.conf"
const ETC = "/etc/apparmor.d"
const SOURCE = "/usr/share/apparmor.d"
const OWN_MARKER = "# managed by arch-dotfiles/apparmor"
const OWN_SUFFIX = ".dotfiles"

def available []: nothing -> list<string> {
    if (which aa-install | is-empty) { die "apparmor.d (aa-install) is not installed" }
    let upstream = if ($SOURCE | path exists) {
        glob $"($SOURCE)/**/*" --no-dir | where not ($it =~ '/(abstractions|tunables)/')
    } else { [] }
    let etc = if ($ETC | path exists) { ls $ETC | where type == file | get name } else { [] }
    $upstream ++ $etc | path basename
    | each {|n| if ($n | str ends-with $OWN_SUFFIX) { $n | str substring 0..<(($n | str length) - ($OWN_SUFFIX | str length)) } else { $n } }
    | uniq | sort
}

def first-word [line: string]: nothing -> string {
    $line | split row --regex '\s+' | first
}

def sudo-save [file: path, --append]: string -> nothing {
    $in | ^sudo tee ...(if $append { [--append] } else { [] }) $file | ignore
}

def mode-set [profile: string, mode: string]: nothing -> nothing {
    if $profile not-in (available) { die $"no apparmor.d profile named '($profile)' \(try: aa list ($profile)\)" }
    ^sudo touch $INCLUDE $FLAGS
    let extra = if ($BASELINE_FLAGS | path exists) {
        open --raw $BASELINE_FLAGS | lines | where (first-word $it) == $profile
        | each { split row --regex '\s+' | get 1 | parse --regex '^[^,]*(?<rest>.*)' | get 0.rest } | str join
    } else { "" }
    open --raw $FLAGS | lines | where (first-word $it) != $profile | append $"($profile) ($mode)($extra)"
    | str join "\n" | $"($in)\n" | sudo-save $FLAGS
    let file = $ETC | path join $"($profile)($OWN_SUFFIX)"
    if ($file | path exists) and (open --raw $file | lines | any { $in == $OWN_MARKER }) {
        let flag = if $mode == "enforce" { "" } else { $"($mode)," }
        open --raw $file | lines | each {|l|
            if ($l | str starts-with "profile ") {
                $l | str replace --regex 'flags=\((complain|unconfined),' 'flags=('
                | str replace 'flags=(' $"flags=\(($flag)"
            } else { $l }
        } | str join "\n" | $"($in)\n" | sudo-save $file
        ^sudo apparmor_parser --replace --write-cache $file
    } else {
        if $profile not-in (open --raw $INCLUDE | lines) { $"($profile)\n" | sudo-save $INCLUDE --append }
        ^sudo aa-install --install
    }
    print $"aa: ($profile) -> ($mode) \(reboot-safe\)"
}

# Show the loaded profiles and their modes, plus your manual choices.
def main []: nothing -> nothing {
    if (which aa-install | is-empty) { die "apparmor.d (aa-install) is not installed" }
    print "# loaded profiles and modes"
    ^sudo aa-status --show=profiles
    print "" $"# your manual choices \(($FLAGS)\)"
    if ($FLAGS | path exists) { open --raw $FLAGS | print --no-newline } else { print "  (none yet)" }
}

# List apparmor.d's profile names; a filter that matches nothing shows all.
def "main list" [filter?: string]: nothing -> string {
    let all = available
    let matched = if $filter == null { [] } else { $all | where ($it | str lowercase) =~ ($filter | str lowercase) }
    if ($matched | is-empty) { $all } else { $matched } | str join "\n"
}

# Confine a profile and block violations.
def "main enforce" [profile: string]: nothing -> nothing { mode-set $profile enforce }

# Confine a profile but only log violations.
def "main complain" [profile: string]: nothing -> nothing { mode-set $profile complain }

# Stop confining a profile (an unconfined profile, so it holds over the baseline).
def "main off" [profile: string]: nothing -> nothing { mode-set $profile unconfined }
