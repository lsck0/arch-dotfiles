# Where dot keeps its state and the primitives every writer uses: the lock, the atomic save, path-kind.

use proc.nu [succeeds]

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
# the login banner of an install chain that ended with modules waiting on the network; the first run that leaves none
# waiting on it removes it
export const PENDING_ISSUE = "/etc/issue.d/dotfiles-pending.issue"
# the login banner of an install chain that reached config with secrets still locked; base/yubikey removes it once they unlock
export const SECRETS_ISSUE = "/etc/issue.d/dotfiles-secrets.issue"
# the Description= of a user-hook's path and service unit (module.nu user-hook) before "<name> hook"; doctor finds hooks by them
export const HOOK_WATCH_PREFIX = "watch for the"
export const HOOK_RUN_PREFIX = "run the"
const LOCKED_SCRIPT = path self locked.nu

# A path under an XDG base dir (config, data, cache, state, runtime), honoring XDG_*_HOME and XDG_RUNTIME_DIR.
export def xdg [kind: string, ...parts: string]: nothing -> path {
    let base = match $kind {
        config => ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config))
        data => ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share))
        cache => ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache))
        state => ($env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state))
        runtime => ($env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)")
        _ => (error make {msg: $"xdg: no base dir '($kind)'"})
    }
    $base | path join ...$parts
}

# A KEY=value file as a record; one pair of surrounding double quotes is dropped, a later key wins, a missing file is {}.
export def env-file-load [file: path]: nothing -> record {
    if not ($file | path exists) { return {} }
    open --raw $file | lines | parse --regex '^(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$'
    | reduce --fold {} {|e, acc| $acc | upsert $e.key ($e.value | str trim | str replace --regex '^"(.*)"$' '$1') }
}

# A file's text, trimmed; fallback when it is missing or unreadable.
export def file-trim [file: path, fallback: any = ""]: nothing -> any {
    try { open --raw $file | str trim } catch { $fallback }
}

# A file's lines that are not blank, none when it is missing or unreadable.
export def file-lines [file: path]: nothing -> list<string> {
    try { open --raw $file | lines | where ($it | str trim) != "" } catch { [] }
}

# The text with each @key@ replaced by its value.
export def text-render [values: record]: string -> string {
    let template = $in
    $values | transpose key value
    | reduce --fold $template {|pair, text| $text | str replace --all $"@($pair.key)@" ($pair.value | into string) }
}

# A consistent copy of a live SQLite database at copy. .backup into an old copy bumps its counter, so an unchanged
# database would differ on every run: it goes into a fresh file renamed over the copy, and a failed one leaves the
# last good copy, not none.
export def sqlite-snapshot [db: path, copy: path]: nothing -> nothing {
    let next = $"($copy).new"
    mkdir ($copy | path dirname)
    rm --force $next
    ^sqlite3 $db $".backup '($next)'"
    mv --force $next $copy
}

# Whether a process of this exact name runs: a theme or reload step only acts on a running app.
export def process-running [name: string]: nothing -> bool {
    succeeds pgrep -x $name
}

# Whether the system has this group.
export def group-exists [name: string]: nothing -> bool {
    succeeds getent group $name
}

# Whether the unit is active, in the user manager with --user.
export def unit-active [unit: string, --user]: nothing -> bool {
    let scope = if $user { [--user] } else { [] }
    succeeds systemctl ...$scope is-active --quiet $unit
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

# Saves through a temp of this process and a rename, so no reader sees half a file; a link stays a link. --mode: the
# file's mode, set on the temp before a byte is in it.
export def save-atomic [file: path, --mode: string]: string -> nothing {
    let text = $in
    let file = if (path-kind $file) == "symlink" { ^readlink -f $file | str trim } else { $file }
    let tmp = $"($file).($nu.pid)-(random chars --length 6).new"
    if $mode != null {
        "" | save --raw $tmp
        ^chmod $mode $tmp
    }
    $text | save --force --raw $tmp
    # the old mode carries over, but never world-writable: a stray one would stick to every later write
    if $mode == null and ($file | path exists) { ^chmod --reference $file $tmp; ^chmod o-w $tmp }
    mv --force $tmp $file
}

# Runs body on a fresh dir under parent (default $TMPDIR), removed after it whether body fails or not.
export def tmp-dir-run [body: closure, --parent: path]: nothing -> any {
    let dir = if $parent == null { mktemp --directory } else { mktemp --directory --tmpdir-path $parent }
    let result = try { do $body $dir } catch {|e| rm --recursive --force $dir; error make $e }
    rm --recursive --force $dir
    $result
}

# Puts next in dest's place by one atomic rename (renameat2 RENAME_EXCHANGE): a power cut leaves the old one or the
# new one, never none. Both sit on one filesystem.
export def path-swap [next: path, dest: path]: nothing -> nothing {
    if (path-kind $dest) == "" { mv $next $dest; return }
    ^mv --exchange --no-target-directory $next $dest
    rm --recursive --force $next
}

# The path type, "" for a missing path or one under a dir this process cannot read (path type fails there).
export def path-kind [path: path]: nothing -> string {
    try { $path | path type | default "" } catch { "" }
}

# Every output of every record of the running layer, or only of the module ids given. A record a prior crash or hand
# edit left unparseable counts as empty, not a reason to fail every module's plan.
export def recorded-outputs [ids?: list<string>]: nothing -> list<record> {
    let dir = state-dir | path join modules
    let files = if $ids == null { glob ($dir | path join **/*.nuon) } else { $ids | each {|id| glob ($dir | path join $id *.nuon) } | flatten }
    $files | par-each --keep-order {|f| try { open $f | get outputs } catch { [] } } | flatten
}

# Newest write per path across all records, so one verb's merge onto another's file is no drift.
export def recorded-hashes []: nothing -> record {
    recorded-outputs | where {|o| $o.kind in [file json ini] and ($o.hash? | default null) != null }
    | sort-by {|o| $o.at? | default 0 }
    | each {|o| [$o.target $o.hash] } | into record
}
