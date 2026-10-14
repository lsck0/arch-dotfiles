use module.nu *
export use ../boot/boot.nu [cmdline-set]

export const meta = {packages: {native: [apparmor apparmor.d]}, volatile: true}

const MANUAL = "/etc/apparmor/flags.d/manual.conf"
const ETC = "/etc/apparmor.d"
const PARSER_CONF = "/etc/apparmor/parser.conf"
const SYSCTL = "/etc/sysctl.d/99-apparmor.conf"
const EARLY_POLICY = "/etc/apparmor/earlypolicy"
# apparmor.d's install guide: the policy cached where systemd loads it before the first unit
const PARSER_LINES = [write-cache $"cache-loc ($EARLY_POLICY)/" Optimize=compress-fast]
# the kernel's CONFIG_LSM default with apparmor before bpf; active after the next reboot
const LSM = "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
# every gui profile reads the ~/.config link targets in the checkout through an abstraction it already includes
const CONFIG_LINK_HOOKS = [desktop fonts qt5 qt6 kde]
const USER_DIRS = "../xdg/user-dirs.dirs"

def rows [file: path]: nothing -> table {
    if not ($file | path exists) { return [] }
    open --raw $file | lines | where {|l| not ($l | str starts-with "#") and ($l | str trim) != "" }
    | parse --regex '^(?<name>\S+)\s+(?<flags>\S+)'
}

def own []: nothing -> list<string> {
    ls profiles | get name | path basename
}

# "<profile> <mode>" in effect: the baseline, then the `aa` command's manual choices
def modes []: nothing -> record {
    rows profiles.conf | append (rows $MANUAL)
    | reduce --fold {} {|r, acc| $acc | upsert $r.name ($r.flags | split row "," | first) }
}

# apparmor.d assumes capitalized xdg dirs, configs/base/xdg's are lowercase; core/syncthing's folder is ~/sync
def xdg-tunables []: nothing -> string {
    open --raw $USER_DIRS | lines | parse --regex '^(?<var>XDG_[A-Z]+_DIR)="\$HOME/(?<dir>.*)"$'
    | each { $'@{($in.var)}+="($in.dir)"' } | append '@{XDG_SYNC_DIR}+="sync"' | str join "\n" | $"($in)\n"
}

def include [abstraction: string]: nothing -> string {
    $"  include <abstractions/dotfiles/($abstraction)>\n"
}

def own-profile [file: path, mode: any]: nothing -> record {
    let text = open --raw $file | lines | each {|l|
        if $mode in [complain unconfined] and ($l | str starts-with "profile ") {
            $l | str replace "flags=(" $"flags=($mode),"
        } else { $l }
    } | str join "\n"
    file-text ($ETC | path join ($file | path basename)) $"($text)\n"
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let upstream = rows profiles.conf | where name not-in (own)
    let lines = {|list| $list | str join "\n" | $"($in)\n" }
    [
        (step cmdline-set $LSM)
        (unit-enable apparmor.service)
        # every denial in the kernel log, which is where they land without auditd
        (file-copy sysctl-apparmor.conf $SYSCTL --then [/usr/lib/systemd/systemd-sysctl $SYSCTL])
        (file-copy modes /etc/apparmor/modes)
        # the baseline; `aa` layers per-app choices into a sibling manual.conf that runs leave alone
        (file-text /etc/apparmor/flags.d/dotfiles.conf (do $lines ($upstream | each { $"($in.name) ($in.flags)" })))
        (file-text /etc/apparmor/include.d/dotfiles.conf (do $lines $upstream.name))
        (file-text $"($ETC)/tunables/xdg-user-dirs.d/apparmor.d.d/dotfiles" (xdg-tunables))
    ] ++ (if not ($"($ETC)/abstractions/base-strict" | path exists) {
        # all below builds on apparmor.d's variables and abstractions and would not compile without them
        []
    } else {
        let modes = modes
        [
            (files-into $"($ETC)/abstractions/dotfiles" ...(glob abstractions/*))
            (files-into $"($ETC)/local" ...(glob local/*))
            ($CONFIG_LINK_HOOKS | each {|h|
                file-text $"($ETC)/abstractions/($h).d/dotfiles-config-links" (include config-links)
            })
            # every QtWebEngine profile builds on apparmor.d's chromium abstraction
            (file-text $"($ETC)/abstractions/common/chromium.d/dotfiles-qtwebengine" (include qtwebengine))
            (glob profiles/* | each {|p| own-profile $p ($modes | get --optional ($p | path basename)) })
        ] | decls-flatten
    }) ++ [(step load)]
}

# apparmor.d's pacman hook reruns aa-install on every transaction; a failed build keeps the loaded policy, and the
# check at the end names what is off
export def load []: nothing -> nothing {
    mkdir $EARLY_POLICY
    let have = open --raw $PARSER_CONF | lines
    let missing = $PARSER_LINES | where $it not-in $have
    if ($missing | is-not-empty) { $"($missing | str join "\n")\n" | save --append $PARSER_CONF }
    if (which aa-install | is-not-empty) and (^aa-install --install --no-reload | complete).exit_code != 0 {
        print "note: apparmor: aa-install failed, the profiles keep their last build"
    }
    if (try { open --raw /sys/module/apparmor/parameters/enabled | str trim } catch { "" }) != "Y" {
        print "apparmor: not active in this kernel yet, the profiles load on the next boot"
        return
    }
    if (^systemctl reload-or-restart apparmor.service | complete).exit_code != 0 {
        print "note: apparmor: reload failed, see journalctl -u apparmor"
    }
    let deployed = (try { ^aa-install --list | lines } catch { [] }) | append (own)
        | each { path basename | str replace --regex '\.apparmor\.d$' "" }
    let loaded = open --raw /sys/kernel/security/apparmor/profiles | lines
        | parse --regex '^(?<name>\S+) \((?<mode>[^)]*)\)' | reduce --fold {} {|p, acc| $acc | upsert $p.name $p.mode }
    let wrong = modes | items {|name, want| {name: $name, want: $want, have: ($loaded | get --optional $name)} }
        | where {|p| $p.name in $deployed and $p.have != $p.want }
    if ($wrong | is-not-empty) {
        let lines = $wrong | each { $"apparmor: ($in.name) is ($in.have | default 'not loaded'), expected ($in.want)" }
        error make {msg: ($lines | str join "\n")}
    }
}

# `aa`: per-app enforce, complain or off, layered into manual.conf (aa.nu)
export def link [cfg: record] {
    link-commands aa.nu
}
