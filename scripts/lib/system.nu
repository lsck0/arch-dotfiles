# root never executes a file a user can write: the user packs, the root entry of the existing copy unpacks

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE]
use secrets.nu [secret-is-plaintext]

# migrations: root runs the system-layer ones (`export const layer = "system"`) from this copy
const SYSTEM_PATHS = [configs migrations platforms profiles scripts]
const SYSTEM_SECRETS = [samba-homelab home-gateways wifi protonvpn-netns.conf ssh_publickey.asc]
export const ENTRY = "scripts/lib/system-apply.nu"

# the secrets group's modules (scripts/lib/modules.nu): their files, never keys/, ride in the root copy like configs/
def private-files [checkout: path, which: string]: nothing -> list<string> {
    let dir = $checkout | path join configs secrets
    if not ($dir | path join .git | path exists) { return [] }
    ^git -C $dir ls-files -z $which --exclude-standard --deduplicate | split row (char nul)
    | where {|f|
        let parts = $f | path split
        let module = $f != "" and ($parts | length) > 1 and $parts.0 != keys and ($dir | path join $parts.0 mod.nu | path exists)
        $module and ($dir | path join $f | path type) == "file" and (secret-is-plaintext ($dir | path join $f))
    }
    | each { $"configs/secrets/($in)" }
}

# every file the root copy holds, by git's view: --cached the tracked, --others the untracked
export def system-files [checkout: path, which: string]: nothing -> list<string> {
    ^git -C $checkout ls-files -z $which --exclude-standard --deduplicate -- ...$SYSTEM_PATHS
    | split row (char nul) | where {|f| $f != "" and ($checkout | path join $f | path type) == "file" }
    | append (private-files $checkout $which)
}

export def system-secrets [wireguard: any]: nothing -> list<string> {
    $SYSTEM_SECRETS | append $"initramfs-ssh/(sys host | get hostname)/sshkeydir/.ed25519.sk" | append ([$wireguard] | flatten | compact | where $it != "")
}

# forward only: refused unless the copy's commit is an ancestor of HEAD (with --rollback a descendant)
export def system-pack [checkout: path, --rollback]: nothing -> binary {
    let head = ^git -C $checkout rev-parse HEAD | str trim
    let source = $SYSTEM_REPO | path join .source
    if ($source | path exists) {
        let old = open --raw $source | str trim
        let forward = (^git -C $checkout merge-base --is-ancestor $old $head | complete).exit_code == 0
        let back = $rollback and (^git -C $checkout merge-base --is-ancestor $head $old | complete).exit_code == 0
        if not $forward and not $back { error make {msg: $"($SYSTEM_REPO) is at ($old), not an ancestor of ($checkout)'s HEAD ($head); keeping it, pull first"} }
        if $back { log-warn $"($SYSTEM_REPO) steps back from ($old) to ($head), an explicit rollback" }
    }
    # links stay out (one could point into /home), a deleted tracked file has nothing to pack
    let tracked = system-files $checkout "--cached"
    # untracked new modules apply before their commit; their mode as is, so a 600 file never turns world-readable
    let untracked = system-files $checkout "--others" | where $it not-in $tracked
    if $ENTRY not-in $tracked and $ENTRY not-in $untracked { error make {msg: $"($checkout) lists no ($ENTRY), not packing"} }
    let tar = mktemp --tmpdir dot-pack.XXXXXX
    $tracked | str join (char nul) | ^tar -C $checkout --no-recursion --null -T - --mode=go=u,go-w -cf $tar
    if ($untracked | is-not-empty) { $untracked | str join (char nul) | ^tar -C $checkout --no-recursion --null -T - --mode=go-w -rf $tar }
    let out = open --raw $tar | into binary
    rm --force $tar
    $out
}

# extracted beside <copy> and swapped in only when complete, so a run never sees a half-written copy
export def system-unpack [copy: path, sha: string]: binary -> nothing {
    if not ($sha =~ '^[0-9a-f]{40}$') { error make {msg: $"($sha) is not a commit sha"} }
    let next = $"($copy).new"
    rm --recursive --force $next
    mkdir $next
    $in | ^tar -x --no-same-owner --no-same-permissions -C $next -f -
    if not ($next | path join $ENTRY | path exists) { error make {msg: $"the archive holds no ($ENTRY)"} }
    $"($sha)\n" | save ($next | path join .source)
    ^chmod -R go-w $next
    ^chmod 755 $next
    rm --recursive --force $copy
    mv $next $copy
}

export def system-archive [checkout: path, wireguard: any, --rollback]: nothing -> binary {
    let work = mktemp --directory
    system-pack $checkout --rollback=$rollback | save --raw ($work | path join repo.tar)
    # flat in $DOTFILES_SECRETS: a system verb reads $DOTFILES_SECRETS/<file> for configs/secrets/keys/<file>
    let dir = if ($checkout | path join configs secrets keys | path exists) { $checkout | path join configs secrets keys } else { $checkout }
    let names = system-secrets $wireguard | where {|n| secret-is-plaintext ($dir | path join $n) }
    $names | str join (char nul) | ^tar -C $dir -c --null -T - -f - | save --raw ($work | path join secrets.tar)
    let out = ^tar -C $work -cf - repo.tar secrets.tar
    rm --recursive --force $work
    $out
}
