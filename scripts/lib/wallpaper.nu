use state.nu [LIB_DIR]

const REPO = path self ../..
const DOT = path self ../dot.nu
const LIST = path self ../wallpaper-list.nu
const PICK = path self ../wallpaper-pick.nu
const FONT = path self ../toggles/toggle-font.nu
const THEMES = path self ../../configs/core/themes
const WAL = ".cache/wal"
const LOCK = "theme.lock"
const LOCK_BUSY = 75
const IPC_TIMEOUT_S = "3"

def wal [...parts: string]: nothing -> path { $nu.home-dir | path join $WAL ...$parts }

# background verbs run detached outside the lock so a hung one never blocks later switches; foreground ones would race
def theme-run [file: path, sync: bool]: nothing -> nothing {
    let background = [nu --no-config-file $DOT theme apply $file --only background]
    if $sync {
        ^$background.0 ...($background | skip 1) | ignore
    } else {
        ^setsid --fork ...$background o+e> /dev/null
    }
    ^nu --no-config-file $DOT theme apply $file --only foreground | ignore
}

export def wallpaper-apply [file: path, sync: bool]: nothing -> nothing {
    # a missing path would link wal/wallpaper to nothing and break every downstream generator
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    # the link lives in ~/.cache/wal, so a relative path would point nowhere
    let file = $file | path expand
    # Background.qml refreshes over IPC only, it does not watch the link
    ^ln -sfn $file (wal wallpaper)
    $"($file)\n" | save --force (wal wallpaper_path)
    # a dead shell reads the link on its next start
    let shell = $nu.home-dir | path join .config quickshell
    do { ^timeout $IPC_TIMEOUT_S quickshell ipc -p $shell call background set $file } | complete | ignore
    # themes name their wallpaper by file name, so a secrets copy matches too
    let theme = glob ($THEMES | path join "*.json") | sort
        | each {|f| {name: ($f | path parse | get stem), spec: (open $f)} }
        | where spec.wallpaper? == ($file | path basename) | get --optional 0
    let nvim_theme = if $theme != null {
        ^wallust cs -s $theme.name
        if ($theme.spec.font? | default "" | is-not-empty) { do { ^$FONT set $theme.spec.font } | complete | ignore }
        $theme.name
    } else {
        # -s skips the escape sequences wallust would write to every open tty
        ^wallust run -s $file
        "pywal"
    }
    # read by nvim's lua/theme.lua at startup and by its theme verb
    $"($nvim_theme)\n" | save --force (wal nvim_theme)
    theme-run $file $sync
}

export def wallpaper-get []: nothing -> string {
    try { ^readlink -f (wal wallpaper) | str trim } catch { "" }
}

# physical pixels of the largest monitor; rotation swaps the axes
export def wallpaper-list []: nothing -> list<string> {
    let monitors = if (which hyprctl | is-empty) { [] } else { try { ^hyprctl monitors -j | from json } catch { [] } }
    let screen = $monitors
        | each { if $in.transform mod 2 == 1 { [$in.height $in.width] } else { [$in.width $in.height] } }
        | sort-by { $in.0 * $in.1 } | last
    ^$LIST ...(if $screen == null { [] } else { [--screen $"($screen.0)x($screen.1)"] }) | lines
}

# single-flighted, so get and list still answer while one runs
export def wallpaper-set [wallpaper: string, --sync]: nothing -> nothing {
    let file = if ($wallpaper | str contains "/") { $wallpaper } else { ^$LIST --resolve $wallpaper | str trim }
    let lock = $env.XDG_RUNTIME_DIR? | default /tmp | path join $LOCK
    let script = $"use wallpaper.nu [wallpaper-apply]; wallpaper-apply ($file | path expand | to nuon) ($sync)"
    let code = try {
        ^flock --nonblock --conflict-exit-code $LOCK_BUSY --close $lock nu --no-config-file -I $LIB_DIR -c $script
        0
    } catch {|e| $e.exit_code? | default 1 }
    if $code == $LOCK_BUSY {
        print -e "Another wallpaper switch is already in progress, skipping."
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
        print "No wallpaper selected."
        return
    }
    wallpaper-set $file
}
