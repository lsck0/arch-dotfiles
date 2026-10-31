use module.nu *
use profile.nu [profile-owner]

export const meta = {
    deps: [programming/task]
    inputs: [/usr/bin/bugwarrior ~/.local/state/bugwarrior ~/.config/task/taskrc]
}

export def packages [cfg: record]: nothing -> record {
    {pacman: (if (profile-owner) { [bugwarrior] } else { [] })}
}

const CONFIG_DIR = ".config/bugwarrior"
const LOG_DIR = ".local/state/bugwarrior"
const TASKRC = ($nu.home-dir | path join .config task taskrc)
const UDA = ($nu.home-dir | path join $CONFIG_DIR uda.taskrc)
const UDA_CACHE = "bugwarrior-uda"
const PACMAN_LOCAL = "/var/lib/pacman/local"

# `bugwarrior uda` starts python on every evaluation: its output kept by the config's hash and the installed version.
def uda-render [config: path]: nothing -> string {
    let version = ls --short-names $PACMAN_LOCAL | get name | where $it =~ '^bugwarrior-\d' | get --optional 0 | default ""
    let key = $"(open --raw $config | hash sha256) ($version)" | hash sha256
    let dir = xdg cache $UDA_CACHE
    let cached = $dir | path join $"($key).taskrc"
    if ($cached | path exists) { return (open --raw $cached) }
    let text = with-env {BUGWARRIORRC: $config} { ^bugwarrior uda }
    mkdir $dir
    glob ($dir | path join "*.taskrc") | each { rm --force $in } | ignore
    $text | save --force $cached
    $text
}

export def link [cfg: record] {
    # taskrc includes uda.taskrc and refuses a missing include: an empty one until the UDAs can be generated
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
            file-text $UDA $"(uda-render ($env.PWD | path join bugwarrior.toml))\n"
        })
    ]
}
