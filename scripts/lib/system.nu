# the root-owned copy the system layer runs from: root never executes a file a user can write, so the admin's checkout
# is packed by the user and unpacked by the root entry (system-apply.nu apply) of the copy already there

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE]
use secrets.nu [secret-is-plaintext]

# what the system layer may read; skills, weblinks, wallpapers and secrets stay out
const SYSTEM_PATHS = [configs platforms profiles scripts]
# secret files the system modules read, streamed on the root step's stdin as data; plus the platform's wireguard config.
# the last one: configs/base/boot/remote-unlock's initramfs host key
const SYSTEM_SECRETS = [samba-homelab home-gateways wifi protonvpn-netns.conf ssh_publickey.asc]
export const ENTRY = "scripts/lib/system-apply.nu"

export def system-secrets [wireguard: any]: nothing -> list<string> {
    $SYSTEM_SECRETS | append $"initramfs-ssh/(sys host | get hostname)/sshkeydir/.ed25519.sk" | append ([$wireguard] | flatten | compact | where $it != "")
}

# system-pack <checkout> [--rollback]: the tracked and untracked (not ignored) files the copy takes, as a tar on stdout;
# forward only: refused unless the copy's commit is an ancestor of HEAD, or with --rollback a descendant of it
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
    let files = ^git -C $checkout ls-files -z --cached --others --exclude-standard --deduplicate -- ...$SYSTEM_PATHS
        | split row (char nul) | where {|f| $f != "" and ($checkout | path join $f | path type) == "file" }
    if $ENTRY not-in $files { error make {msg: $"($checkout) lists no ($ENTRY), not packing"} }
    # modes as a fresh clone has them, whatever the admin's umask
    $files | str join (char nul) | ^tar -C $checkout --no-recursion --null -T - --mode=go=u,go-w -cf -
}

# system-unpack <copy> <sha>: root side; the tar on stdin becomes <copy>, extracted beside it and swapped in only when
# complete, so a run never sees a half-written copy
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

# system-archive <checkout> <wireguard> [--rollback]: one tar of repo.tar (the copy) and secrets.tar (the plaintext
# secrets the system modules read)
export def system-archive [checkout: path, wireguard: any, --rollback]: nothing -> binary {
    let work = mktemp --directory
    system-pack $checkout --rollback=$rollback | save --raw ($work | path join repo.tar)
    let dir = if ($checkout | path join secrets | path exists) { $checkout | path join secrets } else { $checkout }
    let names = system-secrets $wireguard | where {|n| secret-is-plaintext ($dir | path join $n) }
    $names | str join (char nul) | ^tar -C $dir -c --null -T - -f - | save --raw ($work | path join secrets.tar)
    let out = ^tar -C $work -cf - repo.tar secrets.tar
    rm --recursive --force $work
    $out
}
