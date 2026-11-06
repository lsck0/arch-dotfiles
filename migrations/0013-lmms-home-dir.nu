# lmms had no working dir set and made an empty ~/lmms; creating/apps now points it at documents/lmms. Only an
# empty ~/lmms goes.

export def up []: nothing -> nothing {
    let dir = $nu.home-dir | path join lmms
    if ($dir | path type) == dir and (ls --all $dir | is-empty) { rm $dir }
}
