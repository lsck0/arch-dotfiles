#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path join ../../.. | path expand
const SPOTIFY_DIR = ".cache/spotify-player"
# spotify_player writes one .log and one .backtrace per launch
const SPOTIFY_KEEP = 3
const LOG_AGE_MAX = 14day
const LOG_EXTENSIONS = [log backtrace txt]
const INSTALL_LOG_SIZE_MAX = 2MiB
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
    let install_log = $REPO | path join install.log
    let size = if ($install_log | path exists) { ls $install_log | get 0.size } else { 0B }
    if $size > $INSTALL_LOG_SIZE_MAX {
        open --raw $install_log | into binary | bytes at ($size - $INSTALL_LOG_SIZE_MAX | into int)..
        | save --force $"($install_log).new"
        mv --force $"($install_log).new" $install_log
    }
    # claude-*, run-p* and app-*-transient scopes leave failed entries behind
    ^systemctl --user reset-failed | complete | ignore
}
