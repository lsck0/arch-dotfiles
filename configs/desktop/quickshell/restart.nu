#!/usr/bin/env -S nu --no-config-file
# quickshell runs as quickshell.service, restarted on a crash; this restarts it, `prepare` is the unit's ExecStartPre

const UNIT = "quickshell.service"
const QSB_FALLBACK = "/usr/lib/qt6/bin/qsb"
const SETTLE = 300ms

def pgid-of [pid: int]: nothing -> any {
    let stat = $"/proc/($pid)/stat"
    if ($stat | path exists) { open --raw $stat | str replace -r '^.*\) ' '' | split row " " | get 2 | into int }
}

def main [] {
    # a crash loop leaves it start-limited, the key still brings it back
    ^systemctl --user reset-failed $UNIT | complete
    exec systemctl --user restart $UNIT
}

def "main prepare" [] {
    let config = $env.HOME | path join .config/quickshell
    # an instance outside the unit (a manual run, one from before the unit) would draw a second bar: kill whole process
    # groups, quickshell does not reap its helper children; one launched by hyprland may share its process group
    let spared = [(pgid-of $nu.pid) (^pgrep -xo Hyprland | complete | get stdout | str trim | if $in != "" { pgid-of ($in | into int) })]
    # only this user's instance of this config, not ipc clients or other instances
    let pids = ^pgrep -u $env.USER -f $"^\([^ ]*/\)?\(quickshell|qs\)\( -[^ ]+\)* -p ($config)\( |$\)" | complete | get stdout | lines
    for pid in ($pids | into int) {
        let pgid = pgid-of $pid
        # it may have exited since pgrep saw it
        if $pgid != null and $pgid not-in $spared { ^kill -9 -- $"-($pgid)" | complete } else { ^kill -9 $pid | complete }
    }

    # ShaderEffect reads only baked shaders; qsb ships in qt6-shadertools, without it Ui/Glitch.qml skips itself
    let qsb = which qsb | get path.0? | default (if ($QSB_FALLBACK | path exists) { $QSB_FALLBACK })
    if $qsb != null {
        for frag in (glob $"($config)/shaders/*.frag") {
            let baked = $"($frag).qsb"
            if ($baked | path exists) and (ls $baked | get 0.modified) > (ls $frag | get 0.modified) { continue }
            try { ^$qsb --qt6 -o $baked $frag } catch { print -e $"qsb failed: ($frag)" }
        }
    }

    sleep $SETTLE
}
