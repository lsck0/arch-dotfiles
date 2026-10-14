#!/usr/bin/env -S nu --no-config-file
# opens the quickshell picker on the eligible wallpapers, else the fzf picker of `dot theme`

const SUMMON_TIMEOUT = "3s"
const PICK_TIMEOUT = "300"
const SELECTION_WAIT_TRIES = 20

def main [] {
    let dotfiles = $env.QS_DOTFILES_DIR? | default $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)
    let dot = $dotfiles | path join scripts dot.nu
    let runtime = $env.XDG_RUNTIME_DIR? | default /tmp
    let selection = $runtime | path join $"wallpaper-picker.selection.($nu.pid)"
    let done = $runtime | path join $"wallpaper-picker.done.($nu.pid)"
    let payload = {
        themeDirs: ($dotfiles | path join configs core themes)
        mode: 0
        selectionFile: $selection
        doneFile: $done
        selectedImage: ($nu.home-dir | path join .cache wal wallpaper | path expand)
        filterable: true
        showLabels: true
    }

    # summon exits 0 with "unknown" when the plugin failed to load, so only "ok" means a picker is open
    let summoned = ^timeout $SUMMON_TIMEOUT quickshell ipc -p ($nu.home-dir | path join .config quickshell) call shell summon panel.image-picker ($payload | to json -r)
        | complete
    if not ($summoned.stdout =~ ok) {
        print -e "quickshell picker unavailable; falling back to the fzf picker"
        exec $dot theme
    }

    touch $selection
    ^timeout $PICK_TIMEOUT inotifywait -qq -e create -e close_write --include ($done | path basename) $runtime | complete | ignore
    # selection and done are two separate writes
    for _ in 1..$SELECTION_WAIT_TRIES {
        if (ls $selection).0.size > 0b { break }
        sleep 50ms
    }
    let selected = open --raw $selection | lines | get 0? | default ""
    rm -f $selection $done

    if $selected == "" {
        print -e "no wallpaper selected"
        return
    }
    if ($selected | path type) != file {
        print -e $"selected file does not exist: ($selected)"
        exit 1
    }
    exec $dot theme set $selected
}
