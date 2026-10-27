#!/usr/bin/env -S nu --no-config-file

const UNMAP = path self | path expand | path dirname --num-levels 2 | path join spicetify-unmap-classes.nu
const RELOAD = path self | path expand | path dirname --num-levels 2 | path join spotify-reload.nu
const SPOTIFY_SYSTEM = "/opt/spotify"
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_WAIT_S = 300

def main []: nothing -> nothing {
    let prefs = $nu.home-dir | path join .config spotify prefs
    let logged_in = ($prefs | path exists) and (open --raw $prefs | lines | any { str starts-with autologin.username })
    if not $logged_in { return }
    # the xpui.spa trigger fires mid-transaction: wait for pacman to finish
    for _ in 1..$PACMAN_WAIT_S {
        if not ($PACMAN_LOCK | path exists) { break }
        sleep 1sec
    }
    if ($PACMAN_LOCK | path exists) {
        print -e $"spicetify-apply: pacman still busy after ($PACMAN_WAIT_S)s"
        exit 1
    }
    let lock = $env.XDG_RUNTIME_DIR? | default /tmp | path join spicetify-apply.lock
    ^flock $lock $nu.current-exe --no-config-file $env.CURRENT_FILE locked
}

def "main locked" []: nothing -> nothing {
    let dir = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join spotify-patched
    let apps = $dir | path join Apps
    let stamp = $dir | path join .dotfiles-source
    let spa = $SPOTIFY_SYSTEM | path join Apps xpui.spa
    let mtime = if ($spa | path exists) { ^stat -c %Y $spa | str trim } else { "" }
    # spicetify injects extensions only into a fresh copy: a changed list rebuilds it
    let source = $"(^pacman -Q spotify | str trim) ($mtime) (^spicetify config extensions | str trim | lines | str join '|')"
    if not ($stamp | path exists) or (open --raw $stamp | str trim) != $source {
        rm --recursive --force $dir
        mkdir ($dir | path dirname)
        ^cp -a --reflink=auto $SPOTIFY_SYSTEM $dir
        ^chmod -R u+w $dir
        $"($source)\n" | save --force $stamp
    }
    ^spicetify config spotify_path $dir | ignore
    if not ($apps | path join xpui.spa | path exists) and ($apps | path join xpui | path exists) { return }
    # -n: spicetify's restart would start the copy outside spotify-launch.nu's apparmor profile
    try { ^spicetify -n apply } catch { ^spicetify -n backup apply }
    ^spicetify -n enable-devtools
    ^$UNMAP ($apps | path join xpui)
    ^$RELOAD --page
}
