use module.nu *

export const meta = {packages: {pacman: [bugwarrior]}, inputs: [/usr/bin/bugwarrior]}

const CONFIG_DIR = ".config/bugwarrior"
# bugwarrior.toml's log_file
const LOG_DIR = ".local/state/bugwarrior"

# pulls the owner's own issue trackers
export def link [cfg: record] {
    if not (profile-has identity) { return [] }
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let log = $nu.home-dir | path join $LOG_DIR
    [
        (file-copy bugwarrior.toml ($dir | path join bugwarrior.toml))
        (exec bugwarrior-log-dir [mkdir -p $log] --creates $log)
        # taskwarrior rejects bugwarrior's udas unless declared (programming/task includes them)
        (if (which bugwarrior | is-empty) { [] } else {
            file-text ($dir | path join uda.taskrc) $"(with-env {BUGWARRIORRC: ($env.PWD | path join bugwarrior.toml)} { ^bugwarrior uda })\n"
        })
    ]
}
