use module.nu *

export const meta = {deps: [programming/task], packages: {pacman: [bugwarrior]}, inputs: [/usr/bin/bugwarrior]}

const CONFIG_DIR = ".config/bugwarrior"
const LOG_DIR = ".local/state/bugwarrior"
const TASKRC = ($nu.home-dir | path join .config task taskrc)
const UDA = ($nu.home-dir | path join $CONFIG_DIR uda.taskrc)

export def link [cfg: record] {
    # taskrc includes uda.taskrc unconditionally and taskwarrior refuses to start on a missing include, so bugwarrior
    # owns the file on every machine: an empty placeholder until the real UDAs can be generated below.
    # owner-identifying config (the GitHub login) still rolls out only when actually unlocked, not on profile alone.
    if not (owner-unlocked) {
        if (profile-has secrets) { log-warn "bugwarrior: secrets locked, owner config not rolled out" }
        return [(file-text $UDA "")]
    }
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let log = $nu.home-dir | path join $LOG_DIR
    [
        (file-copy bugwarrior.toml ($dir | path join bugwarrior.toml))
        (exec bugwarrior-log-dir [mkdir -p $log] --creates $log)
        # `bugwarrior uda` opens the log file and the taskrc while planning; keep the empty placeholder until both exist
        (if (which bugwarrior | is-empty) or not ($log | path exists) or not ($TASKRC | path exists) {
            file-text $UDA ""
        } else {
            file-text $UDA $"(with-env {BUGWARRIORRC: ($env.PWD | path join bugwarrior.toml)} { ^bugwarrior uda })\n"
        })
    ]
}
