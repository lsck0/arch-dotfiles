#!/usr/bin/env -S nu --no-config-file
const USAGE = "usage: desktop-run [options] -- <command...>"
const EXIT_USAGE = 2
const EXIT_INTERRUPTED = 130
const OPEN_TRIES = 120
const NOTIFY_EARLY = 5sec
const NOTIFY_LINES = 5

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

# Runs a launcher entry's command: a pick appended, sudo unless in --group, a failure held in a terminal or notified.
def main [
    ...command: any  # any: nu parses a bare true or 3 as a bool or number, a string type would reject it
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
        let errfile = mktemp --tmpdir "desktop-run-XXXXXX"
        # stdout inherits the journal and stderr streams to a file, so nothing is held in memory for the app's lifetime
        try { ^($command | first) ...($command | skip 1) e> $errfile } catch { }
        let exit_code = $env.LAST_EXIT_CODE
        let stderr_text = open --raw $errfile
        rm --force $errfile
        print --stderr --no-newline $stderr_text
        let early = ((date now) - $started) < $NOTIFY_EARLY
        if $exit_code != 0 or ($early and ($stderr_text | str trim | is-not-empty)) {
            try { ^notify-send -a $title $"($title) did not start" ($stderr_text | lines | last $NOTIFY_LINES | str join "\n") }
        }
        exit $exit_code
    }
    let status = try { ^($command | first) ...($command | skip 1); 0 } catch { $env.LAST_EXIT_CODE }
    if (is-terminal --stdin) and ($hold or ($status != 0 and $status != $EXIT_INTERRUPTED)) {
        print $"\n[($title) exited with ($status), any key closes]"
        try { input listen --types [key] | ignore }
    }
    exit $status
}
