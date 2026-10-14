# third-party code pinned by content: a moved tag or a compromised upstream fails here instead of running

use state.nu [state-dir path-kind]

def fetch-cache []: nothing -> path {
    if (is-admin) { "/var/cache/dotfiles/fetch" } else { $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dotfiles fetch }
}

def stamp [dest: path]: nothing -> path {
    state-dir | path join fetched ($dest | path expand | hash sha256)
}

export def fetch-file-done [sha256: string, dest: path]: nothing -> bool {
    ($dest | path exists) and (try { open --raw (stamp $dest) | str trim } catch { "" }) == $sha256
}

export def fetch-git-done [commit: string, dir: path]: nothing -> bool {
    (^git -C $dir rev-parse HEAD | complete | get stdout | str trim) == $commit
}

def extract [archive: path, into: path]: nothing -> nothing {
    mkdir $into
    if (^file -b --mime-type $archive | str trim) == "application/zip" { ^unzip -q $archive -d $into } else { ^tar -xf $archive -C $into }
}

# a large download resumes where it stopped (curl -C -); the cache keeps it by its hash for the next machine state
export def fetch-file-run [url: string, sha256: string, dest: path, --mode: string = "644", --extract: string]: nothing -> nothing {
    let cached = fetch-cache | path join $sha256
    if not ($cached | path exists) {
        mkdir ($cached | path dirname)
        ^curl -fsSL --retry 3 -C - -o $"($cached).part" $url
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
    rm --recursive --force $dest
    mv $next $dest
    mkdir (stamp $dest | path dirname)
    $sha256 | save --force (stamp $dest)
}

# <dir> checked out at exactly <commit>, submodules at its gitlinks
export def fetch-git-run [url: string, commit: string, dir: path]: nothing -> nothing {
    if (fetch-git-done $commit $dir) { return }
    ^git init -q $dir
    ^git -C $dir fetch -q --depth 1 $url $commit
    ^git -C $dir -c advice.detachedHead=false checkout -q $commit
    ^git -C $dir submodule -q update --init --recursive --depth 1
}
