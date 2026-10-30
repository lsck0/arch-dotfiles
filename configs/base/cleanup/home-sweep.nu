#!/usr/bin/env -S nu --no-config-file

# spotify_player hardcodes ~/.cache, ignoring XDG_CACHE_HOME
const SPOTIFY_DIR = ".cache/spotify-player"
const SPOTIFY_KEEP = 3
const LOG_AGE_MAX = 14day
const LOG_EXTENSIONS = [log backtrace txt]
const APP_LOGS = [
    [dir process];
    [.xlcore/logs XIVLauncher]
    [.local/share/ModrinthApp/launcher_logs ModrinthApp]
    [.local/state/Heroic/logs heroic]
]

def app-running [pattern: string]: nothing -> bool {
    (^pgrep -f -- $pattern | complete).exit_code == 0
}

def logs-in [dir: path, extensions: list<string>]: nothing -> table {
    let dir = $nu.home-dir | path join $dir
    if not ($dir | path exists) { return [] }
    ls --all $dir | where type == file and ($it.name | path parse | get extension) in $extensions
}

def main []: nothing -> nothing {
    if not (app-running spotify_player) {
        for ext in [log backtrace] {
            logs-in $SPOTIFY_DIR [$ext] | sort-by modified --reverse | skip $SPOTIFY_KEEP
            | each { rm $in.name } | ignore
        }
    }
    for app in ($APP_LOGS | where not (app-running $it.process)) {
        logs-in $app.dir $LOG_EXTENSIONS | where modified < ((date now) - $LOG_AGE_MAX) | each { rm $in.name } | ignore
    }
    # clear the failed state of user units so an old failure does not mask a fresh one
    ^systemctl --user reset-failed | complete | ignore
}
