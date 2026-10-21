use module.nu *

export const meta = {deps: [programming/task], packages: {pacman: [bugwarrior]}, inputs: [/usr/bin/bugwarrior]}

const CONFIG_DIR = ".config/bugwarrior"
const LOG_DIR = ".local/state/bugwarrior"
const TASKRC = ($nu.home-dir | path join .config task taskrc)

export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let log = $nu.home-dir | path join $LOG_DIR
    [
        (file-copy bugwarrior.toml ($dir | path join bugwarrior.toml))
        (exec bugwarrior-log-dir [mkdir -p $log] --creates $log)
        # `bugwarrior uda` opens the log file and the taskrc while planning
        (if (which bugwarrior | is-empty) or not ($log | path exists) or not ($TASKRC | path exists) { [] } else {
            file-text ($dir | path join uda.taskrc) $"(with-env {BUGWARRIORRC: ($env.PWD | path join bugwarrior.toml)} { ^bugwarrior uda })\n"
        })
    ]
}
