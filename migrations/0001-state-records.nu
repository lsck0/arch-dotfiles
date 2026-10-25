# The module records become dot's one store: the written file (the hash dot last wrote per path) folds into
# them as each output's write time (at, ns) plus an owned merge's own entry, then goes; root's generations
# file goes with rollback --full. The old files are kept under migrated/0001 for down.

use state.nu [state-dir]

const BACKUP = "migrated/0001"
const OLD = [written written.seen written.lock generations]

def ns [time: any]: nothing -> int {
    try { $time | into datetime | into int } catch { 0 }
}

# Folds <dir>/written into the records under <dir>/modules; the newest write per path becomes the one whose
# hash the written file holds, a hash no file output has becomes a merge entry in each record of its module.
export def convert [dir: path]: nothing -> nothing {
    let modules = $dir | path join modules
    let backup = $dir | path join $BACKUP
    mkdir $backup
    for f in $OLD { if ($dir | path join $f | path exists) { cp -p ($dir | path join $f) $backup } }
    if ($modules | path exists) { cp -rp $modules $backup }
    let written = if ($dir | path join written | path exists) {
        open --raw ($dir | path join written) | lines | where $it != "" | split column "\t" path sum
        | reduce --fold {} {|r, acc| $acc | upsert $r.path $r.sum }
    } else { {} }
    let files = glob ($modules | path join **/*.nuon)
    let records = $files | each {|f|
        let rec = open $f
        let at = ns $rec.time
        let id = $f | path dirname | path relative-to $modules
        {file: $f, id: $id, rec: ($rec | update outputs { each {|o| if $o.kind == "file" { $o | upsert at $at } else { $o } } })}
    }
    let entries = $records | each {|r| $r.rec.outputs | where kind == file | each { {target: $in.target, hash: $in.hash, at: $in.at, id: $r.id} } } | flatten
    # per written path: the newest time any record holds for it, plus one, marks dot's last write
    let marks = $written | items {|path, sum|
        let own = $entries | where target == $path
        {path: $path, sum: $sum, at: (($own | get at | append 0 | math max) + 1), matched: ($own | any { $in.hash == $sum }), ids: ($own | get id | uniq)}
    }
    let lost = $marks | where not $it.matched and ($it.ids | is-empty)
    if ($lost | is-not-empty) { print $"0001: no record holds ($lost.path | str join ' '), what dot wrote there is no longer recorded" }
    for r in $records {
        let mine = $marks | where {|m| $r.id in $m.ids }
        let outputs = $r.rec.outputs | each {|o|
            let m = $mine | where path == $o.target | get --optional 0
            if $o.kind == "file" and $m != null and $m.matched and $o.hash == $m.sum { $o | update at $m.at } else { $o }
        }
        let merges = $mine | where not $it.matched | each {|m|
            {kind: (if ($m.path | str ends-with ".json") { "json" } else { "ini" }), target: $m.path, hash: $m.sum, at: $m.at}
        }
        $r.rec | update outputs ($outputs ++ $merges) | to nuon | save --force $r.file
    }
    for f in $OLD { rm --force ($dir | path join $f) }
}

# Puts the old files and records back from the backup up made.
export def restore [dir: path]: nothing -> nothing {
    let backup = $dir | path join $BACKUP
    if not ($backup | path exists) { error make {msg: $"0001: no backup at ($backup), nothing to restore"} }
    for f in $OLD { if ($backup | path join $f | path exists) { cp -p ($backup | path join $f) $dir } }
    if ($backup | path join modules | path exists) {
        rm --recursive --force ($dir | path join modules)
        cp -rp ($backup | path join modules) $dir
    }
}

export def up []: nothing -> nothing { convert (state-dir) }
export def down []: nothing -> nothing { restore (state-dir) }
