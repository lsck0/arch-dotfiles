#!/usr/bin/env -S nu --no-config-file

const UNMAP = path self | path expand | path dirname --num-levels 2 | path join spicetify-unmap-classes.nu
const RELOAD = path self | path expand | path dirname --num-levels 2 | path join spotify-reload.nu
const SPOTIFY_SYSTEM = "/opt/spotify"
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_WAIT_S = 300
const EXIT_WAIT_S = 10

def config-home []: nothing -> path { $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) }

def patched-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join spotify-patched
}

def logged-in []: nothing -> bool {
    let prefs = config-home | path join spotify prefs
    ($prefs | path exists) and (open --raw $prefs | lines | any { str starts-with autologin.username })
}

# What the patched copy was made from: the package, its xpui.spa and the extension list spicetify injects.
def source-text []: nothing -> string {
    let spa = $SPOTIFY_SYSTEM | path join Apps xpui.spa
    let mtime = if ($spa | path exists) { ^stat -c %Y $spa | str trim } else { "" }
    $"(^pacman -Q spotify | str trim) ($mtime) (^spicetify config extensions | str trim | lines | str join '|')"
}

def applied []: nothing -> bool {
    let apps = patched-dir | path join Apps
    not ($apps | path join xpui.spa | path exists) and ($apps | path join xpui | path exists)
}

# Whether a run would patch anything: logged in, and the copy stale, unapplied or not the one spicetify points at.
export def apply-pending []: nothing -> bool {
    if not (logged-in) { return false }
    let stamp = patched-dir | path join .dotfiles-source
    let ini = config-home | path join spicetify config-xpui.ini
    let path = if ($ini | path exists) { open --raw $ini | parse --regex '(?m)^spotify_path\s*=\s*(?<v>.*?)\s*$' | get --optional 0.v }
    not (applied) or $path != (patched-dir) or not ($stamp | path exists) or (open --raw $stamp | str trim) != (source-text)
}

def main []: nothing -> nothing {
    if not (logged-in) { return }
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
    let dir = patched-dir
    let apps = $dir | path join Apps
    let stamp = $dir | path join .dotfiles-source
    # spicetify injects extensions only into a fresh copy: a changed list rebuilds it
    let source = source-text
    if not ($stamp | path exists) or (open --raw $stamp | str trim) != $source {
        rm --recursive --force $dir
        mkdir ($dir | path dirname)
        ^cp -a --reflink=auto $SPOTIFY_SYSTEM $dir
        ^chmod -R u+w $dir
        $"($source)\n" | save --force $stamp
    }
    ^spicetify config spotify_path $dir | ignore
    if (applied) { return }
    # -n: spicetify's restart would start the copy outside spotify-launch.nu's apparmor profile
    try { ^spicetify -n apply } catch { ^spicetify -n backup apply }
    ^spicetify -n enable-devtools
    ^$UNMAP ($apps | path join xpui)
    if (stock-running) { restart } else { ^$RELOAD --page }
}

# A spotify started before the first patch (a fresh install logs in only after autostart) runs the stock binary, which
# a page reload cannot patch.
def stock-running []: nothing -> bool {
    ^pgrep -x spotify | lines | any {|pid|
        (try { ^readlink $"/proc/($pid)/exe" | str trim } catch { "" }) | str starts-with $"($SPOTIFY_SYSTEM)/"
    }
}

# Restarts it through its desktop entry, so spotify-launch.nu runs the patched copy; a service, not a scope, so uwsm
# returns and spotify outlives this hook's unit.
def restart []: nothing -> nothing {
    ^pkill -x spotify
    for _ in 1..$EXIT_WAIT_S {
        if (^pgrep -x spotify | complete).exit_code != 0 { break }
        sleep 1sec
    }
    ^uwsm app -t service -S both -- spotify.desktop
}
