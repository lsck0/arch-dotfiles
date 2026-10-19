use log.nu *
use state.nu [LIB_DIR path-kind]

const PLAN_AREA_MAX = 10
const PLAN_AREA_DEPTH = 3
# disk filesystems an overlay may cover below a writable root; anything else (network, fuse, autofs) stays hidden
const PLAN_DISK_FS = [btrfs ext2 ext3 ext4 xfs f2fs vfat exfat]
const PLAN_BIN = "/run/dotfiles-plan/bin"
const PLAN_SYSTEMCTL = path self plan-systemctl.nu
const PLAN_ROOT_CAPS = [CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID CAP_SETUID CAP_SETGID]

export def plan-active []: nothing -> bool {
    ($env.DOTFILES_PLAN? | is-not-empty) and ($env.DOTFILES_PLAN_DIR? | is-not-empty)
}

export def plan-note [action: string, path: string, detail: string = ""]: nothing -> nothing {
    if not (plan-active) {
        return
    }
    let module = $env.DOTFILES_PLAN_MODULE? | default driver
    $"($module)\t($action)\t($path)\t($detail)\n" | save --append ($env.DOTFILES_PLAN_DIR | path join notes)
}

export def plan-snapshot-units [dir: path, scope: string]: nothing -> nothing {
    ^systemctl $"--($scope)" list-unit-files --no-legend --no-pager
    | lines | where $it != "" | each { split row --regex '\s+' | take 2 | str join " " } | str join "\n"
    | $"($in)\n" | save --force ($dir | path join $"unit-files.($scope)")
    ^systemctl $"--($scope)" list-units --no-legend --no-pager --plain --state=active
    | lines | where $it != "" | each { split row --regex '\s+' | first } | str join "\n"
    | $"($in)\n" | save --force ($dir | path join $"active.($scope)")
}

export def plan-sandbox [dir: path, roots: list<path>, command: list<string>]: nothing -> int {
    if (which bwrap | is-empty) {
        error make {msg: "plan mode needs bwrap (bubblewrap)"}
    }
    mkdir ($dir | path join upper) ($dir | path join work)
    let mounts = ^findmnt -rno TARGET,FSTYPE | lines | parse "{target} {fstype}"
    let overlays = $roots
        | where ($it | path exists)
        | each {|root| ^realpath -e $root }
        | each {|root|
            let below = $mounts
                | where {|m| ($m.target | str starts-with $"($root)/") and $m.fstype in $PLAN_DISK_FS }
                | get target
            [$root] | append $below
        }
        | flatten | uniq | sort
        | enumerate
        | each {|row| {n: ($row.index + 1), target: $row.item} }
    $overlays | each {|o| $"($o.n)\t($o.target)" } | str join "\n" | $"($in)\n" | save --force ($dir | path join overlays)
    let overlay_args = $overlays | each {|o|
        let upper = $dir | path join upper ($o.n | into string)
        let work = $dir | path join work ($o.n | into string)
        mkdir $upper $work
        [--overlay-src $o.target --overlay $upper $work $o.target]
    } | flatten
    let runtime_args = if ($env.XDG_RUNTIME_DIR? | is-empty) { [] } else { [--perms "0700" --dir $env.XDG_RUNTIME_DIR] }
    let secrets_args = if ($env.DOTFILES_SECRETS? | is-empty) { [] } else { [--ro-bind $env.DOTFILES_SECRETS $env.DOTFILES_SECRETS] }
    let cap_args = if (is-admin) { [--cap-drop ALL] ++ ($PLAN_ROOT_CAPS | each {|cap| [--cap-add $cap] } | flatten) } else { [] }
    let args = [
        --ro-bind / / --dev /dev --proc /proc --unshare-net --unshare-pid --unshare-ipc --unshare-uts
        --die-with-parent --new-session --setenv DOTFILES_PLAN 1 --setenv DOTFILES_PLAN_SANDBOX 1
        --setenv DOTFILES_PLAN_DIR $dir
        ...$overlay_args
        --tmpfs /tmp --tmpfs /run --tmpfs /dev/shm --tmpfs /var/tmp --bind $dir $dir
        --dir $PLAN_BIN --ro-bind $PLAN_SYSTEMCTL ($PLAN_BIN | path join systemctl)
        --setenv PATH $"($PLAN_BIN):($env.PATH | str join ':')"
        ...$runtime_args ...$secrets_args ...$cap_args
    ]
    let status = try { ^bwrap ...$args -- ...$command; 0 } catch {|e| $e.exit_code? | default 1 }
    $status
}

export def plan-end [dir: path]: nothing -> nothing {
    if ($dir | path exists) {
        # an overlay leaves its work dir unreadable
        try { ^chmod -R u+rwx ($dir | path join work) }
        rm --recursive --force $dir
    }
}

export def plan-report [dir: path, failures: path]: nothing -> string {
    let notes_file = $dir | path join notes
    let decisions = if ($notes_file | path exists) {
        open --raw $notes_file | lines | where $it != "" | split column "\t" module action path detail
        | sort-by --natural module | group-by module --to-table
        | each {|group|
            [$group.module] ++ ($group.items | each {|n|
                let detail = if ($n.detail | is-empty) { "" } else { $"  \(($n.detail)\)" }
                $"  ($n.action | fill --width 10) ($n.path)($detail)"
            })
        } | flatten
    } else { [] }
    let stopped = if ($failures | path exists) and (open --raw $failures | str trim | is-not-empty) {
        ["=== stopped early (the plan of these is partial) ==="] ++ (open --raw $failures | lines | where $it != "" | each { $"  ($in)" })
    } else { [] }
    let full = $env.DOTFILES_PLAN_FULL? | is-not-empty
    let writes = plan-write-set $dir | group-by area --to-table | each {|area|
        if $full or ($area.items | length) <= $PLAN_AREA_MAX {
            $area.items | each {|w| $"  ($w.kind | fill --width 2) ($w.path)" }
        } else {
            let counts = [["+" new] ["~" changed] ["-" removed] ["->" links]]
                | each {|k| let n = $area.items | where kind == $k.0 | length; if $n > 0 { $" ($n) ($k.1)" } else { "" } }
                | str join
            [$"  ** ($area.area)/ \(($area.items | length) paths:($counts)\)"]
        }
    } | flatten
    let head = if ($decisions | is-empty) { [] } else { ["=== decisions ==="] ++ $decisions }
    $head ++ $stopped ++ ["=== write set ==="] ++ $writes | str join "\n"
}

def plan-write-set [dir: path]: nothing -> table {
    let overlays_file = $dir | path join overlays
    if not ($overlays_file | path exists) {
        return []
    }
    let logs = $env.DOTFILES? | default "/nonexistent"
    open --raw $overlays_file | lines | where $it != "" | split column "\t" n target | each {|o|
        let upper = $dir | path join upper $o.n
        let depth = ($o.target | path split | length) + $PLAN_AREA_DEPTH
        ^find $upper -mindepth 1 -printf '%y\t%P\t%l\n' | lines | sort | each {|line|
            let f = $line | split row "\t"
            let path = $o.target | path join $f.1
            let kind = match $f.0 {
                c => "-"
                d => (if ($path | path exists) { null } else { "+" })
                l => "->"
                _ => (if (path-kind $path) != "" { "~" } else { "+" })
            }
            let shown = if $kind == "->" { $"($path) -> ($f.2)" } else { $path }
            let is_log = (($path | str starts-with $"($logs)/") and (($path | str ends-with ".log") or ($path | path basename | str starts-with "FAILURES."))) or ($path =~ '/dotfiles/runs/')
            if $kind == null or $is_log {
                null
            } else {
                {area: ($path | path split | take $depth | path join), kind: $kind, path: $shown}
            }
        } | compact
    } | flatten
}
