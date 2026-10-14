# the bash libraries' state paths, so both engines share one state

export const SYSTEM_REPO = "/var/lib/dotfiles/repo"
export const SYSTEM_STATE = "/var/lib/dotfiles"
export const LIB_DIR = path self .
# root runs nu only by absolute path, never what a user's PATH resolves
export const NU_ROOT = "/usr/bin/nu"
const LOCKED_SCRIPT = path self locked.nu

# the system layer's state is root's even when a user plans it
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

# nu holds no fd lock, so the critical section is a process of its own under flock, the bash helpers' lock too
export def state-locked [lock: path, op: string, args: record]: nothing -> nothing {
    mkdir ($lock | path dirname)
    $args | to json --raw | ^flock $lock (nu-bin) --no-config-file --stdin -I $LIB_DIR $LOCKED_SCRIPT $op
}

# path type fails on a missing path instead of answering nothing
export def path-kind [path: path]: nothing -> string {
    try { $path | path type | default "" } catch { "" }
}
