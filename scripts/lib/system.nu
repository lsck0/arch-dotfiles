# Root never runs user-writable files: the user packs repo and secrets, the root copy unpacks them.

use log.nu *
use state.nu [SYSTEM_REPO]
use secrets.nu [secret-is-plaintext]
use modules.nu [modules-discover modules-root-run]

const SYSTEM_PATHS = [configs migrations platforms profiles scripts]
const SYSTEM_SECRETS = [samba-homelab home-gateways trusted-gateways wifi protonvpn-netns.conf ssh_publickey.asc]
export const ENTRY = "scripts/lib/system-apply.nu"
export const SECRETS_PREFIX = "configs/secrets/"
export const SECRETS_DIGEST = ".secrets-digest"

# The secrets group's module files (never keys/), which ride in the root copy like configs/.
def private-files [checkout: path, which: string]: nothing -> list<string> {
    let dir = $checkout | path join configs secrets
    if not ($dir | path join .git | path exists) { return [] }
    ^git -C $dir ls-files -z $which --exclude-standard --deduplicate | split row (char nul)
    | where {|f|
        let parts = $f | path split
        let module = $f != "" and ($parts | length) > 1 and $parts.0 != keys and ($dir | path join $parts.0 mod.nu | path exists)
        $module and ($dir | path join $f | path type) == "file" and (secret-is-plaintext ($dir | path join $f))
    }
    | each { $"($SECRETS_PREFIX)($in)" }
}

# One sha256 over the secrets group's files, which the root copy keeps root-only, so the user compares without
# reading them.
export def secrets-digest [dir: path, files: list<string>]: nothing -> string {
    $files | sort | each {|f| $"(open --raw ($dir | path join $f) | hash sha256)  ($f)" } | str join "\n" | hash sha256
}

# Each module dir under configs/ (relative, the secrets group's included) and whether root runs any of its hooks.
def module-dirs-root [checkout: path]: nothing -> record {
    let base = $checkout | path expand
    let modules = modules-discover $base [] | where group != ""
    let root = modules-root-run $modules
    $modules | reduce --fold {} {|m, acc| $acc | insert ($m.dir | path relative-to $base) ($m.id in $root) }
}

# Whether root can read f: any .nu file (a root-run module may import it), anything outside a module under configs/
# (the root modules scripts and skills included, whole), and every file of a module root runs a hook of.
def root-reads [f: string, modules: record]: nothing -> bool {
    if ($f | str ends-with ".nu") { return true }
    mut dir = $f | path dirname
    while $dir not-in ["" "."] {
        let root = $modules | get --optional $dir
        if $root != null { return $root }
        $dir = $dir | path dirname
    }
    true
}

# Every file the root copy holds, by git's view: --cached the tracked, --others the untracked. The non-.nu files of a
# module root never runs stay out, so the app state backup and update write after the pack leaves the copy current.
export def system-files [checkout: path, which: string]: nothing -> list<string> {
    let modules = module-dirs-root $checkout
    ^git -C $checkout ls-files -z $which --exclude-standard --deduplicate -- ...$SYSTEM_PATHS
    | split row (char nul) | where {|f| $f != "" and ($checkout | path join $f | path type) == "file" }
    | append (private-files $checkout $which)
    | where {|f| root-reads $f $modules }
}

# The secrets the system layer may read, relative to configs/secrets/keys/.
export def system-secrets [wireguard: any]: nothing -> list<string> {
    $SYSTEM_SECRETS | append $"initramfs-ssh/(sys host | get hostname)/sshkeydir/.ed25519.sk" | append ([$wireguard] | flatten | compact | where $it != "")
}

# Refused only when HEAD is behind the copy (no rollback); a copy commit gone from history only warns.
export def system-pack [checkout: path, copy: path = $SYSTEM_REPO]: nothing -> binary {
    let head = ^git -C $checkout rev-parse HEAD | str trim
    let source = $copy | path join .source
    if ($source | path exists) {
        let old = open --raw $source | str trim
        let ancestor = {|a, b| (^git -C $checkout merge-base --is-ancestor $a $b | complete).exit_code == 0 }
        if $old != $head and not (do $ancestor $old $head) {
            if (do $ancestor $head $old) { error make {msg: $"($copy) is at ($old), ahead of ($checkout)'s HEAD ($head); keeping it, pull first"} }
            log-warn $"($copy) was at ($old), which ($checkout)'s history no longer has; replacing it with ($head)"
        }
    }
    let tracked = system-files $checkout "--cached"
    let untracked = system-files $checkout "--others" | where $it not-in $tracked
    if $ENTRY not-in $tracked and $ENTRY not-in $untracked { error make {msg: $"($checkout) lists no ($ENTRY), not packing"} }
    let tar = mktemp --tmpdir dot-pack.XXXXXX
    $tracked | str join (char nul) | ^tar -C $checkout --no-recursion --null -T - --mode=go=u,go-w -cf $tar
    # untracked new modules apply before their commit; their mode as is, so a 600 file never turns world-readable
    if ($untracked | is-not-empty) { $untracked | str join (char nul) | ^tar -C $checkout --no-recursion --null -T - --mode=go-w -rf $tar }
    let out = open --raw $tar | into binary
    rm --force $tar
    $out
}

# Extracts the tar beside copy and swaps it in only when complete, so a run never sees a half-written copy.
export def system-unpack [copy: path, sha: string]: binary -> nothing {
    if not ($sha =~ '^[0-9a-f]{40}$') { error make {msg: $"($sha) is not a commit sha"} }
    let next = $"($copy).new"
    rm --recursive --force $next
    mkdir $next
    ^chmod 700 $next
    $in | ^tar -x --no-same-owner --no-same-permissions -C $next -f -
    if not ($next | path join $ENTRY | path exists) { error make {msg: $"the archive holds no ($ENTRY)"} }
    $"($sha)\n" | save ($next | path join .source)
    let secrets = $next | path join $SECRETS_PREFIX
    let private = if ($secrets | path exists) { ^find $secrets -type f -print0 | split row (char nul) | where $it != "" | path relative-to $next } else { [] }
    secrets-digest $next $private | save ($next | path join $SECRETS_DIGEST)
    ^chmod -R go-w $next
    if ($secrets | path exists) { ^chmod -R go= $secrets }
    ^chmod 755 $next
    # one atomic rename (renameat2 RENAME_EXCHANGE): a power cut leaves the old copy or the new one, never none
    if ($copy | path exists) {
        ^mv --exchange --no-target-directory $next $copy
        rm --recursive --force $next
    } else {
        mv $next $copy
    }
}

# The repo tar and the plaintext system secrets, flat as DOTFILES_SECRETS/<file>, in one tar for system-apply.
export def system-archive [checkout: path, wireguard: any]: nothing -> binary {
    let work = mktemp --directory
    system-pack $checkout | save --raw ($work | path join repo.tar)
    let dir = if ($checkout | path join configs secrets keys | path exists) { $checkout | path join configs secrets keys } else { $checkout }
    let names = system-secrets $wireguard | where {|n| secret-is-plaintext ($dir | path join $n) }
    $names | str join (char nul) | ^tar -C $dir -c --null -T - -f - | save --raw ($work | path join secrets.tar)
    let out = ^tar -C $work -cf - repo.tar secrets.tar
    rm --recursive --force $work
    $out
}
