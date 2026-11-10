# Where dot keeps its state and the primitives every writer uses: the lock, the atomic save, path-kind.

export const SYSTEM_REPO = "/var/lib/dotfiles/repo"
export const SYSTEM_STATE = "/var/lib/dotfiles"
export const LIB_DIR = path self .
# root runs nu only by absolute path, never what a user's PATH resolves
export const NU_ROOT = "/usr/bin/nu"
# the install subprocess exit code for a user-aborted install; shared across the stage, run and system-apply boundaries
export const EXIT_ABORTED = 2
# a run that left work pending (a system part skipped, a module waiting on its packages); nothing failed
export const EXIT_PENDING = 3
# root's install writes it once its pacman pass went through; the install stage clears it first and reads it after
export const INSTALL_PASS_FILE = $SYSTEM_STATE | path join install-pass
# the login banner of an install chain whose config stage failed; the next clean full dot apply removes it
export const CONFIG_ISSUE = "/etc/issue.d/dotfiles-config.issue"
const LOCKED_SCRIPT = path self locked.nu

# A path under an XDG base dir (config, data, cache, state), honoring XDG_*_HOME.
export def xdg [kind: string, ...parts: string]: nothing -> path {
    let base = match $kind {
        config => ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config))
        data => ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share))
        cache => ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache))
        state => ($env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state))
        _ => (error make {msg: $"xdg: no base dir '($kind)'"})
    }
    $base | path join ...$parts
}

# The running layer's state dir; the system layer's is root's even when a user plans it.
export def state-dir []: nothing -> path {
    if (is-admin) or ($env.DOT_LAYER? == "system") {
        $SYSTEM_STATE
    } else {
        xdg state dotfiles
    }
}

export def nu-bin []: nothing -> string {
    if (is-admin) { $NU_ROOT } else { "nu" }
}

# Runs op of locked.nu under flock on lock: nu holds no fd lock, so the critical section is a process of its own.
export def state-locked [lock: path, op: string, args: record]: nothing -> any {
    mkdir ($lock | path dirname)
    $args | to json --raw | ^flock $lock (nu-bin) --no-config-file --stdin -I $LIB_DIR $LOCKED_SCRIPT $op
}

# Saves through a temp of this process and a rename, so no reader sees half a file; a link stays a link.
export def save-atomic [file: path]: string -> nothing {
    let file = if (path-kind $file) == "symlink" { ^readlink -f $file | str trim } else { $file }
    let tmp = $"($file).($nu.pid)-(random chars --length 6).new"
    $in | save --force --raw $tmp
    # the old mode carries over, but never world-writable: a stray one would stick to every later write
    if ($file | path exists) { ^chmod --reference $file $tmp; ^chmod o-w $tmp }
    mv --force $tmp $file
}

# The path type, "" for a missing path (path type fails on one instead of answering nothing).
export def path-kind [path: path]: nothing -> string {
    try { $path | path type | default "" } catch { "" }
}

# Newest write per path across all records, so one verb's merge onto another's file is no drift. A record a prior
# crash or hand edit left unparseable counts as empty, not a reason to fail every module's plan.
export def recorded-hashes []: nothing -> record {
    glob (state-dir | path join modules **/*.nuon) | par-each --keep-order {|f| try { open $f | get outputs } catch { [] } } | flatten
    | where {|o| $o.kind in [file json ini] and ($o.hash? | default null) != null }
    | sort-by {|o| $o.at? | default 0 }
    | reduce --fold {} {|o, acc| $acc | upsert $o.target $o.hash }
}
