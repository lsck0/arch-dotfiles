#!/usr/bin/env -S nu --no-config-file
# opens the quickshell image picker, which runs `dot theme <image>` on Enter; without quickshell, dot's fzf picker

const SUMMON_TIMEOUT = "3s"

def main [--themes] {
    let payload = {
        mode: (if $themes { 1 } else { 0 })
        selectedImage: ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join wal wallpaper | path expand)
    }
    # summon exits 0 with "unknown" when the plugin failed to load, so only "ok" means a picker is open
    let summoned = ^timeout $SUMMON_TIMEOUT quickshell ipc -p ($nu.home-dir | path join .config quickshell) call shell summon panel.image-picker ($payload | to json -r)
        | complete
    if not ($summoned.stdout =~ ok) {
        print -e "quickshell picker unavailable; falling back to the fzf picker"
        exec ($nu.home-dir | path join .local bin dot) theme
    }
}
