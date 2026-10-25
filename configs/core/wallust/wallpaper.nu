# Wallpaper switching for `dot theme` and the bar: link the image, recolor with wallust (a themes/*.json naming the
# wallpaper wins), then run every module's theme verb.

use font.nu [font-save]

const INTERNAL = path self ../../../scripts/lib/internal.nu
const LIST = path self wallpaper-list.nu
const PICK = path self wallpaper-pick.nu
const THEMES = path self ../../../themes
const WAL = ".cache/wal"
# the one pending switch, the wallpaper's path and a nonce: callers write it, dot-theme.path starts UNIT while it
# exists, and the run renames it to TAKEN before applying, so a request written meanwhile is a new file
const REQUEST = "theme.request"
const TAKEN = "theme.taken"
const UNIT = "dot-theme.service"
const IPC_TIMEOUT_S = "3"

def wal [...parts: string]: nothing -> path { $nu.home-dir | path join $WAL ...$parts }

def request-file []: nothing -> path { $env.XDG_RUNTIME_DIR? | default /tmp | path join $REQUEST }

def request-pending []: nothing -> bool { request-file | path exists }

# The newest request, moved aside so the path unit only sees what arrives after it; "" when none waits.
def request-take []: nothing -> string {
    let taken = $env.XDG_RUNTIME_DIR? | default /tmp | path join $TAKEN
    if (do { ^mv -f (request-file) $taken } | complete).exit_code != 0 { return "" }
    try { open --raw $taken | str trim } catch { "" }
}

# Links `file` and recolors with wallust; false when a newer request arrived meanwhile, so the theme verbs of this
# palette would be wasted. A theme's font applies only when the wallpaper changes: a re-run on the same one (toggle-font
# asks for it) keeps the font just picked.
def recolor [file: path]: nothing -> bool {
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    let switched = (wallpaper-get) != ($file | path expand)
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
        if $switched and ($theme.spec.font? | default "" | is-not-empty) { font-save {family: $theme.spec.font} }
        $theme.name
    } else {
        ^wallust run -s $file
        "pywal"
    }
    $"($nvim_theme)\n" | save --force (wal nvim_theme)
    not (request-pending)
}

# The unit's body: applies the newest request, one per run, so the unit's timeout bounds one switch; a request
# written meanwhile keeps the file there and dot-theme.path starts the next run, so a burst costs at most the running
# switch plus the last.
export def theme-serve []: nothing -> nothing {
    let request = request-take
    if $request == "" { return }
    let file = $request | lines | first
    # a failed verb is the theme apply's own report; the run still succeeds, so dot-theme.service keeps a newer request
    try {
        if (recolor $file) { ^nu --no-config-file $INTERNAL theme apply $file }
    } catch {|e| print --stderr $"theme: ($file | path basename): ($e.msg)" }
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

# Switches to a path or a wallpaper name: the newest request wins, the unit runs one switch at a time. --sync waits
# for every theme verb. Before the unit is installed (a fresh home's first apply) the switch runs here.
export def wallpaper-set [wallpaper: string, --sync]: nothing -> nothing {
    let file = if ($wallpaper | str contains "/") { $wallpaper } else {
        let found = do { ^$LIST --resolve $wallpaper } | complete
        if $found.exit_code != 0 { error make {msg: ($found.stderr | str trim)} }
        $found.stdout | str trim
    }
    let file = $file | path expand
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    let request = request-file
    $"($file)\n(random uuid)\n" | save --force $"($request).tmp"
    ^mv -f $"($request).tmp" $request
    if (do { ^systemctl --user cat $UNIT } | complete).exit_code != 0 {
        theme-serve
        return
    }
    # dot-theme.path starts the run; --sync starts it too: a start joins a run already going and returns when it ends,
    # so the loop returns once the run that took this request is done, not only once the request was taken
    if not $sync { return }
    loop {
        let started = do { ^systemctl --user start $UNIT } | complete
        if $started.exit_code != 0 {
            error make {msg: $"wallpaper: switching to ($file) failed, journalctl --user -u ($UNIT)"}
        }
        if not (request-pending) { break }
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
