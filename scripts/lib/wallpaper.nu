# Wallpaper switching for `dot theme` and the bar: link the image, recolor with wallust (a themes/*.json naming the
# wallpaper wins), then run every module's theme verb.

use state.nu [LIB_DIR]

const REPO = path self ../..
const INTERNAL = path self internal.nu
const LIST = path self wallpaper-list.nu
const PICK = path self wallpaper-pick.nu
const FONT = path self ../toggles/toggle-font.nu
const THEMES = path self ../../themes
const WAL = ".cache/wal"
const LOCK = "theme.lock"
const BACKGROUND_LOCK = "theme-background.lock"
# the token of the newest request: a queued switch or background run that finds another one there was superseded
const WANT = "theme.want"
const LOCK_BUSY = 75
const LOCK_WAIT_S = "120"
const IPC_TIMEOUT_S = "3"

def wal [...parts: string]: nothing -> path { $nu.home-dir | path join $WAL ...$parts }

def runtime [name: string]: nothing -> path { $env.XDG_RUNTIME_DIR? | default /tmp | path join $name }

export def superseded [token: string]: nothing -> bool {
    (try { open --raw (runtime $WANT) | str trim } catch { "" }) != $token
}

# The background verbs of one switch, run one switch at a time: a stale palette never lands after a newer one, and
# a queued run a newer switch replaced is dropped. One that waited out a hung run goes ahead unlocked.
export def theme-background [file: path, token: string]: nothing -> nothing {
    let script = $"use wallpaper.nu [superseded]; if not \(superseded ($token | to nuon)\) { ^nu --no-config-file ($INTERNAL | to nuon) theme apply ($file | to nuon) --only background }"
    let run = [nu --no-config-file -I $LIB_DIR -c $script]
    let code = try {
        ^flock --wait $LOCK_WAIT_S --conflict-exit-code $LOCK_BUSY --close (runtime $BACKGROUND_LOCK) ...$run
        0
    } catch {|e| $e.exit_code? | default 1 }
    if $code == $LOCK_BUSY { ^$run.0 ...($run | skip 1) }
}

# Background verbs run detached outside the switch's lock, so a slow one never delays the next switch.
def theme-run [file: path, sync: bool, token: string]: nothing -> nothing {
    let background = [nu --no-config-file -I $LIB_DIR -c $"use wallpaper.nu [theme-background]; theme-background ($file | to nuon) ($token | to nuon)"]
    if $sync {
        ^$background.0 ...($background | skip 1) | ignore
    } else {
        ^setsid --fork ...$background o+e> /dev/null
    }
    ^nu --no-config-file $INTERNAL theme apply $file --only foreground | ignore
}

# Switches to `file` unlocked; callers go through wallpaper-set, which serializes it and drops superseded requests.
export def wallpaper-apply [file: path, sync: bool, token: string]: nothing -> nothing {
    if (superseded $token) {
        print -e "wallpaper: a newer switch replaced this one, skipping"
        return
    }
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    let file = $file | path expand
    ^ln -sfn $file (wal wallpaper)
    $"($file)\n" | save --force (wal wallpaper_path)
    let shell = $nu.home-dir | path join .config quickshell
    do { ^timeout $IPC_TIMEOUT_S quickshell ipc -p $shell call background set $file } | complete | ignore
    let theme = glob ($THEMES | path join "*.json") | sort
        | each {|f| {name: ($f | path parse | get stem), path: $f, spec: (open $f)} }
        | where spec.wallpaper? == ($file | path basename) | get --optional 0
    let nvim_theme = if $theme != null {
        # by path: wallust matches a name as a prefix, so gruvbox-dark was ambiguous with gruvbox-dark-soft
        ^wallust cs -s --wallpaper $file $theme.path
        if ($theme.spec.font? | default "" | is-not-empty) { do { ^$FONT set $theme.spec.font } | complete | ignore }
        $theme.name
    } else {
        ^wallust run -s $file
        "pywal"
    }
    $"($nvim_theme)\n" | save --force (wal nvim_theme)
    theme-run $file $sync $token
}

export def wallpaper-get []: nothing -> string {
    try { ^readlink -f (wal wallpaper) | str trim } catch { "" }
}

# Wallpapers fitting the largest monitor in physical pixels, rotation swapping the axes.
export def wallpaper-list []: nothing -> list<string> {
    let monitors = if (which hyprctl | is-empty) { [] } else { try { ^hyprctl monitors -j | from json } catch { [] } }
    let screen = $monitors
        | each { if $in.transform mod 2 == 1 { [$in.height $in.width] } else { [$in.width $in.height] } }
        | sort-by { $in.0 * $in.1 } | last
    ^$LIST ...(if $screen == null { [] } else { [--screen $"($screen.0)x($screen.1)"] }) | lines
}

# Switches to a path or a wallpaper name. Switches run one at a time and the newest request wins: one queued
# behind a running switch is dropped when a newer one arrives meanwhile.
export def wallpaper-set [wallpaper: string, --sync]: nothing -> nothing {
    let file = if ($wallpaper | str contains "/") { $wallpaper } else {
        let found = do { ^$LIST --resolve $wallpaper } | complete
        if $found.exit_code != 0 { error make {msg: ($found.stderr | str trim)} }
        $found.stdout | str trim
    }
    let token = random uuid
    $"($token)\n" | save --force (runtime $WANT)
    let script = $"use wallpaper.nu [wallpaper-apply]; wallpaper-apply ($file | path expand | to nuon) ($sync) ($token | to nuon)"
    let code = try {
        ^flock --wait $LOCK_WAIT_S --conflict-exit-code $LOCK_BUSY --close (runtime $LOCK) nu --no-config-file -I $LIB_DIR -c $script
        0
    } catch {|e| $e.exit_code? | default 1 }
    if $code == $LOCK_BUSY {
        print -e "wallpaper: the running switch did not finish in time, skipping"
    } else if $code != 0 {
        error make {msg: $"wallpaper: switching to ($file) failed"}
    }
}

export def wallpaper-random [--sync]: nothing -> nothing {
    let all = wallpaper-list
    if ($all | is-empty) { error make {msg: "no eligible wallpaper"} }
    wallpaper-set ($all | shuffle | first) --sync=$sync
}

export def wallpaper-pick []: nothing -> nothing {
    let picked = do { wallpaper-list | str join "\n" | ^$PICK } | complete
    if $picked.exit_code != 0 { error make {msg: "no eligible wallpaper"} }
    let file = $picked.stdout | str trim
    if $file == "" {
        print "wallpaper: none picked"
        return
    }
    wallpaper-set $file
}
