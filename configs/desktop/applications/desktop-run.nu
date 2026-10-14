#!/usr/bin/env -S nu --no-config-file
# desktop-run [--file|--files|--dir|--ask <p>] [--in-dir] [--cd <dir>] [--open <url>] [--group <g>] [--hold] [--notify] -- <cmd...>
# a launcher entry's command: a pick appended, sudo unless in <group>, a failure held in a terminal or notified from a gui

const USAGE = "usage: desktop-run [options] -- <command...>"
const EXIT_USAGE = 2
# left with ctrl+c, on purpose
const EXIT_INTERRUPTED = 130
# polled, a server takes from a second (mitmweb) to a minute (a cold jvm) to listen
const OPEN_TRIES = 120
const NOTIFY_EARLY = 5sec
const NOTIFY_LINES = 5

# null when cancelled: a cancelled pick or an empty answer cancels the launch, not an error
def --wrapped zenity-ask [...args: string]: nothing -> any {
    let out = ^zenity ...$args | complete
    if $out.exit_code != 0 { null } else { $out.stdout | str trim --right --char "\n" }
}

def picked [pick: string, title: string]: nothing -> any {
    let answer = match $pick {
        file => (zenity-ask --file-selection $"--title=($title): open")
        files => (zenity-ask --file-selection --multiple "--separator=\n" $"--title=($title): open")
        dir => (zenity-ask --file-selection --directory $"--title=($title): folder")
    }
    if $answer == null { null } else { $answer | lines }
}

def asked [prompt: string, title: string]: nothing -> any {
    let answer = if (is-terminal --stdin) {
        try { input $"($prompt): " } catch { null }
    } else {
        zenity-ask --entry $"--title=($title)" $"--text=($prompt)"
    }
    if ($answer | is-empty) { null } else { [$answer] }
}

def open-when-up [url: string]: nothing -> nothing {
    job spawn {
        for _ in 1..$OPEN_TRIES {
            if (^curl -fso /dev/null --max-time 1 $url | complete).exit_code == 0 {
                ^xdg-open $url o+e>| ignore
                return
            }
            sleep 1sec
        }
    } | ignore
}

# typed `any`: nu parses a bare true or 3 in the command as a bool or number, a string type would reject it
def main [
    ...command: any
    --file, --files, --dir
    --ask: string
    --in-dir
    --cd: string
    --open: string
    --group: string
    --hold
    --notify
]: nothing -> nothing {
    let command = $command | each { into string }
    if ($command | is-empty) or ([$file $files $dir] | where $it | length) > 1 {
        print --stderr $USAGE
        exit $EXIT_USAGE
    }
    let pick = if $file { "file" } else if $files { "files" } else if $dir { "dir" }
    let title = $command.0 | path basename
    let extra = if $pick != null { picked $pick $title } else if $ask != null { asked $ask $title } else { [] }
    if $extra == null { return }
    if $in_dir {
        let workdir = zenity-ask --file-selection --directory $"--title=($title): run in"
        if $workdir == null { return }
        cd $workdir
    } else if $cd != null {
        mkdir $cd
        cd $cd
    }
    if $open != null { open-when-up $open }
    let sudo = $group != null and $group not-in (^id -nG | str trim | split row " ")
    let command = (if $sudo { [sudo] } else { [] }) ++ $command ++ $extra

    if $notify and not (is-terminal --stdin) {
        let started = date now
        let out = ^($command | first) ...($command | skip 1) | complete
        print --stderr --no-newline $out.stderr
        if $out.exit_code != 0 or ((date now) - $started) < $NOTIFY_EARLY {
            try { ^notify-send -a $title $"($title) did not start" ($out.stderr | lines | last $NOTIFY_LINES | str join "\n") }
        }
        exit $out.exit_code
    }
    let status = try { ^($command | first) ...($command | skip 1); 0 } catch { $env.LAST_EXIT_CODE }
    if (is-terminal --stdin) and ($hold or ($status != 0 and $status != $EXIT_INTERRUPTED)) {
        print $"\n[($title) exited with ($status), any key closes]"
        try { input listen --types [key] | ignore }
    }
    exit $status
}
