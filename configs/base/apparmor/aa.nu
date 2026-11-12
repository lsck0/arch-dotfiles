#!/usr/bin/env -S nu --no-config-file
# aa: per-machine apparmor modes (flags.d/include.d manual.conf), layered over the dotfiles baseline

const REPO = path self | path expand | path dirname | path join ../../.. | path expand
use ($REPO | path join scripts lib usage.nu) [die]
use ($REPO | path join configs base apparmor profile-flags.nu) [ETC MARKER OWN_SUFFIX text-mode upstream-files]

const INCLUDE = "/etc/apparmor/include.d/manual.conf"
const FLAGS = "/etc/apparmor/flags.d/manual.conf"
const BASELINE_FLAGS = "/etc/apparmor/flags.d/dotfiles.conf"

def available []: nothing -> list<string> {
    if (which aa-install | is-empty) { die "apparmor.d (aa-install) is not installed" }
    let etc = if ($ETC | path exists) { ls $ETC | where type == file | get name } else { [] }
    # an own profile's <name>.dotfiles and the <name>.apparmor.d that replaces a stock profile are both <name>
    (upstream-files) ++ $etc | path basename | str replace --regex $'($OWN_SUFFIX)$|\.apparmor\.d$' ''
    | uniq | sort
}

def sudo-save [file: path]: string -> nothing {
    $in | ^sudo tee $file | ignore
}

def mode-set [profile: string, mode: string]: nothing -> nothing {
    if $profile not-in (available) { die $"no apparmor.d profile named '($profile)' \(try: aa list ($profile)\)" }
    ^sudo touch $INCLUDE $FLAGS
    # the baseline's extra flags (attach_disconnected, ...) stay with the new mode
    let extra = if ($BASELINE_FLAGS | path exists) {
        open --raw $BASELINE_FLAGS | parse --regex '(?m)^(?<name>\S+)[ \t]+[^,\s]*(?<rest>\S*)' | where name == $profile
        | get rest | str join
    } else { "" }
    open --raw $FLAGS | lines | where ($it | split row --regex '\s+' | first) != $profile
    | append $"($profile) ($mode)($extra)" | str join "\n" | $"($in)\n" | sudo-save $FLAGS
    let file = $ETC | path join $"($profile)($OWN_SUFFIX)"
    if ($file | path exists) and (open --raw $file | lines | any { $in == $MARKER }) {
        open --raw $file | text-mode $mode | sudo-save $file
        ^sudo apparmor_parser --replace --write-cache $file
    } else {
        if $profile not-in (open --raw $INCLUDE | lines) { $"($profile)\n" | ^sudo tee --append $INCLUDE | ignore }
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
