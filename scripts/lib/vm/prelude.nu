export const HOST = "@HOST@"

export def say [key: string, value: string]: nothing -> nothing { print $"drill: ($key)=($value)" }

export def yesno []: bool -> string { if $in { "yes" } else { "no" } }

export def succeeds [command: closure]: nothing -> bool { (do $command | complete).exit_code == 0 }

# stdout of a command that may fail, as bash's $(...) gives it; its stderr still reaches the log
export def output [command: closure]: nothing -> string {
    let run = do $command | complete
    print --stderr --no-newline $run.stderr
    $run.stdout | str trim --right
}

export def package-version [pkgbase: string]: nothing -> string {
    output { ^pacman -Q $pkgbase } | split row " " | get --optional 1 | default ""
}

# a step that reboots must report first
export def report []: nothing -> nothing { do --ignore-errors { ^curl -sT $"($env.CURRENT_FILE).log" $"http://($HOST)/drill.log" } }
