# Pinned downloads: files by sha256, git trees by commit.

use state.nu [state-dir path-kind xdg]
use online.nu [remote-pending]

# git has no retry of its own: a remote's 5xx or 429 gets these waits before the fetch fails (curl retries files itself)
const GIT_RETRY_WAITS = [5sec 20sec]

def fetch-cache []: nothing -> path {
    if (is-admin) { "/var/cache/dotfiles/fetch" } else { xdg cache dotfiles fetch }
}

def stamp [dest: path]: nothing -> path {
    state-dir | path join fetched ($dest | path expand | hash sha256)
}

export def fetch-file-done [sha256: string, dest: path]: nothing -> bool {
    ($dest | path exists) and (try { open --raw (stamp $dest) | str trim } catch { "" }) == $sha256
}

# A download already in the cache needs no network to land.
export def fetch-file-cached [sha256: string]: nothing -> bool {
    fetch-cache | path join $sha256 | path exists
}

export def fetch-git-done [commit: string, dir: path]: nothing -> bool {
    (^git -C $dir rev-parse HEAD | complete | get stdout | str trim) == $commit
}

def extract [archive: path, into: path]: nothing -> nothing {
    mkdir $into
    if (^file -b --mime-type $archive | str trim) == "application/zip" { ^unzip -q $archive -d $into } else { ^tar -xf $archive -C $into }
}

# --extract names an archive member, or . for all; --in-place keeps an existing file's inode for watchers.
export def fetch-file-run [url: string, sha256: string, dest: path, --mode: string = "644", --extract: string, --in-place]: nothing -> nothing {
    let cached = fetch-cache | path join $sha256
    if not ($cached | path exists) {
        mkdir ($cached | path dirname)
        # --retry-all-errors: mirrors drop mid-transfer outside curl's default set; -C - resumes
        let got = ^curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -C - -o $"($cached).part" $url | complete
        if $got.exit_code != 0 { error make {msg: $"download of ($url) failed: ($got.stderr | str trim | lines | last)"} }
        if (open --raw $"($cached).part" | hash sha256) != $sha256 {
            rm --force $"($cached).part"
            error make {msg: $"($url) does not match its pinned sha256 ($sha256)"}
        }
        mv --force $"($cached).part" $cached
    }
    mkdir ($dest | path dirname)
    let next = $"($dest).dot-new"
    rm --recursive --force $next
    if $extract == null {
        ^install -m $mode $cached $next
    } else if $extract == "." {
        extract $cached $next
    } else {
        let tmp = mktemp --directory --tmpdir-path ($dest | path dirname)
        extract $cached $tmp
        let member = $tmp | path join $extract
        if (path-kind $member) == "dir" { mv $member $next } else { ^install -m $mode $member $next }
        rm --recursive --force $tmp
    }
    if $in_place and (path-kind $dest) == "file" and (path-kind $next) == "file" {
        ^chmod $mode $dest
        ^cp $next $dest
        rm $next
    } else {
        rm --recursive --force $dest
        mv $next $dest
    }
    mkdir (stamp $dest | path dirname)
    $sha256 | save --force (stamp $dest)
}

# A shallow checkout of url at commit in dir, submodules included.
export def fetch-git-run [url: string, commit: string, dir: path]: nothing -> nothing {
    if (fetch-git-done $commit $dir) { return }
    ^git init -q $dir
    mut got = ^git -C $dir fetch -q --depth 1 $url $commit | complete
    for wait in $GIT_RETRY_WAITS {
        if $got.exit_code == 0 or (remote-pending $got.stderr) == null { break }
        sleep $wait
        $got = ^git -C $dir fetch -q --depth 1 $url $commit | complete
    }
    if $got.exit_code != 0 { error make {msg: $"git fetch of ($url) failed: ($got.stderr | str trim | lines | last)"} }
    ^git -C $dir -c advice.detachedHead=false checkout -q $commit
    ^git -C $dir submodule -q update --init --recursive --depth 1
}
