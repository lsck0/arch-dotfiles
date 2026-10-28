# Where dot keeps its state and the primitives every writer uses: the lock, the atomic save, path-kind.

export const SYSTEM_REPO = "/var/lib/dotfiles/repo"
export const SYSTEM_STATE = "/var/lib/dotfiles"
export const LIB_DIR = path self .
# root runs nu only by absolute path, never what a user's PATH resolves
export const NU_ROOT = "/usr/bin/nu"
# the install subprocess exit code for a user-aborted install; shared across the stage, run and system-apply boundaries
export const EXIT_ABORTED = 2
const LOCKED_SCRIPT = path self locked.nu

# The running layer's state dir; the system layer's is root's even when a user plans it.
export def state-dir []: nothing -> path {
    if (is-admin) or ($env.DOT_LAYER? == "system") {
        $SYSTEM_STATE
    } else {
        $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join dotfiles
    }
}

export def nu-bin []: nothing -> string {
    if (is-admin) { $NU_ROOT } else { "nu" }
}

# Runs op of locked.nu under flock on lock: nu holds no fd lock, so the critical section is a process of its own.
export def state-locked [lock: path, op: string, args: record]: nothing -> nothing {
    mkdir ($lock | path dirname)
    $args | to json --raw | ^flock $lock (nu-bin) --no-config-file --stdin -I $LIB_DIR $LOCKED_SCRIPT $op
}

# Saves through a temp of this process and a rename, so no reader sees half a file; a link stays a link.
export def save-atomic [file: path]: string -> nothing {
    let file = if (path-kind $file) == "symlink" { ^readlink -f $file | str trim } else { $file }
    let tmp = $"($file).($nu.pid)-(random chars --length 6).new"
    $in | save --force --raw $tmp
    if ($file | path exists) { ^chmod --reference $file $tmp }
    mv --force $tmp $file
}

# The path type, "" for a missing path (path type fails on one instead of answering nothing).
export def path-kind [path: path]: nothing -> string {
    try { $path | path type | default "" } catch { "" }
}
