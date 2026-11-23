# Git clone urls and checkout names from a full url or a github user/repo shorthand, and the repositories under a dir.

const GITHUB = "https://github.com"
# an owner has no dots, a repo may start with one (.github) but is no dot segment
const GITHUB_SHORTHAND = '^[A-Za-z0-9][A-Za-z0-9_-]*/(?!\.\.?$)[A-Za-z0-9_.-]+$'
# dependency and cache trees, never searched for repositories
const SEARCH_PRUNED = [.cache .cargo .direnv .venv elpa node_modules target vendor]
# a linked worktree's .git file; a submodule's points into the parent's .git/modules instead
const WORKTREE_GITDIR = '^gitdir: .*/worktrees/[^/]+/?$'

# A url (with a scheme, or scp-like git@) as given, user/repo as its github https url, null for anything else.
export def repository-url [spec: string]: nothing -> oneof<string, nothing> {
    if $spec =~ '://' or ($spec | str starts-with "git@") { return $spec }
    if $spec =~ $GITHUB_SHORTHAND { return $"($GITHUB)/($spec | str replace --regex '\.git$' '').git" }
    null
}

export def repository-name [url: string]: nothing -> string {
    $url | str replace --regex '\.git$' '' | path basename
}

# A HEAD file's dir or a .git file found under a search dir as a repository, null for neither.
def repository-from-entry [entry: path]: nothing -> oneof<record, nothing> {
    if ($entry | path type) == file {
        let gitdir = open --raw $entry | lines | get 0? | default ""
        return (if $gitdir =~ $WORKTREE_GITDIR { {dir: ($entry | path dirname), kind: worktree} })
    }
    if ($entry | path join objects | path type) != dir or ($entry | path join refs | path type) != dir { return null }
    if ($entry | path basename) == .git { {dir: ($entry | path dirname), kind: checkout} } else { {dir: $entry, kind: bare} }
}

# Every repository at most depth levels below dir (a bare one one level more), sorted: a checkout, a bare repository,
# or a linked worktree.
export def repository-find-under [dir: path, depth: int]: nothing -> table<dir: path, kind: string> {
    let pruned = $SEARCH_PRUNED | each { [-name $in -o] } | flatten
    (^find $dir -maxdepth ($depth + 2) -type d "(" ...$pruned -path "*/.git/*" ")" -prune
        -o -type f -name HEAD -printf "%h\n" -o -type f -name .git -printf "%p\n")
    | lines | each {|entry| repository-from-entry $entry } | sort-by dir
}
