# Git, with clone recursing into submodules: no git config covers them on the initial clone.
def --wrapped git [...rest] {
    if (($rest | length) > 0) and (($rest | first) == "clone") {
        ^git clone --recurse-submodules ...($rest | skip 1)
    } else {
        ^git ...$rest
    }
}
