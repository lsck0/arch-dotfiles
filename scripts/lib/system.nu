# Root never runs user-writable files: the user packs repo and secrets, the root copy unpacks them.

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE nu-bin]
use secrets.nu [secret-is-plaintext]
use modules.nu [modules-discover modules-root-run]

const SYSTEM_PATHS = [configs migrations platforms profiles scripts]
export const ENTRY = "scripts/lib/system-apply.nu"
export const SECRETS_PREFIX = "configs/secrets/"
export const SECRETS_DIGEST = ".secrets-digest"
# root's record of the keys/ secrets its last config stage was handed, as secrets-digest: wheel reads it, nobody else
export const SYSTEM_SECRETS_DIGEST = $SYSTEM_STATE | path join secrets-digest
# what root's last `apply` ran for which run: {run, root_run, stages: [{stage, code, failures}]}
export const SYSTEM_STAGES = $SYSTEM_STATE | path join stages.nuon
export const RUN_ID = '^\d{8}T\d{6}-[a-z0-9]{4}$'
const PARSE_CHECK_LIMIT = 50
# in the signature of an `apply` that takes the asking run's id; an entry without it rejects the flag before its body
const ENTRY_RUN_FLAG = "--run: string"

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
    $modules | each {|m| [($m.dir | path relative-to $base) ($m.id in $root)] } | into record
}

# Whether root can read f: any .nu file (a root-run module may import it), anything outside a module under configs/
# (the root module scripts/ included, whole), and every file of a module root runs a hook of.
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

# The secrets the system layer may read, relative to configs/secrets/keys/: each module's meta.secrets ({host} this
# machine's name) and the platform's wireguard configs. Never outside keys/.
export def system-secrets [repo: path, wireguard: any]: nothing -> list<string> {
    let host = sys host | get hostname
    let declared = modules-discover $repo [] | each { $in.meta.secrets? | default [] } | flatten | str replace --all "{host}" $host
    let names = $declared | append ([$wireguard] | flatten | compact | where $it != "") | uniq
    let outside = $names | where {|n| ($n | str starts-with "/") or ($n | path split | any { $in == ".." }) }
    if ($outside | is-not-empty) { error make {msg: $"secrets outside keys/: ($outside | str join ' ')"} }
    $names
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

# Whether repo's entry parses with this nu, its imports included; nothing of it runs. A root copy whose entry does not
# parse could never unpack its own replacement.
export def entry-parses [repo: path]: nothing -> bool {
    let run = ^(nu-bin) --no-config-file --ide-check $PARSE_CHECK_LIMIT ($repo | path join $ENTRY) | complete
    $run.exit_code == 0 and not ($run.stdout | lines | any {|l| (try { $l | from json | get --optional severity } catch { null }) == "Error" })
}

# Whether repo's entry takes `apply ... --run <id>`, read from its text: the root copy is world-readable.
export def entry-takes-run [repo: path]: nothing -> bool {
    try { open --raw ($repo | path join $ENTRY) | str contains $ENTRY_RUN_FLAG } catch { false }
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
    if not (entry-parses $next) {
        rm --recursive --force $next
        error make {msg: $"the archive's ($ENTRY) does not parse, ($copy) stays as it was: nu --ide-check ($PARSE_CHECK_LIMIT) ($ENTRY) names the error"}
    }
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

# The system secrets this checkout holds in plaintext: their dir and their names in it.
def secrets-plain [checkout: path, wireguard: any]: nothing -> record {
    let dir = if ($checkout | path join configs secrets keys | path exists) { $checkout | path join configs secrets keys } else { $checkout }
    {dir: $dir, names: (system-secrets $checkout $wireguard | where {|n| secret-is-plaintext ($dir | path join $n) })}
}

# The digest root records of the secrets system-archive would hand it now.
export def system-secrets-digest [checkout: path, wireguard: any]: nothing -> string {
    let plain = secrets-plain $checkout $wireguard
    secrets-digest $plain.dir $plain.names
}

# The repo tar and the plaintext system secrets, flat as DOTFILES_SECRETS/<file>, in one tar for system-apply.
export def system-archive [checkout: path, wireguard: any]: nothing -> binary {
    let work = mktemp --directory
    system-pack $checkout | save --raw ($work | path join repo.tar)
    let plain = secrets-plain $checkout $wireguard
    $plain.names | str join (char nul) | ^tar -C $plain.dir -c --null -T - -f - | save --raw ($work | path join secrets.tar)
    let out = ^tar -C $work -cf - repo.tar secrets.tar
    rm --recursive --force $work
    $out
}
