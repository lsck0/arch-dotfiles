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
    # a re-run replaces the backup, cp -r would merge into it and bring removed modules back on down
    rm --recursive --force ($backup | path join modules)
    if ($modules | path exists) { cp -rp $modules $backup }
    let written_file = $dir | path join written
    let written_at = if ($written_file | path exists) { ls $written_file | get 0.modified | into int } else { 0 }
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
    # a hash the written file holds but a record wrote over later is stale: the new engine ran before this
    # migration (a sync's install, a theme switch), the record is current
    let marks = $marks | where {|m| $m.matched or ($m.at - 1) <= $written_at }
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

# Back to the old shape from the records as they are now, so every write since up stays known: the written
# file gets the newest hash per path across file and merge entries, the records lose at and the merge entries.
# The generations file comes back from the backup, it only lists history.
export def restore [dir: path]: nothing -> nothing {
    let modules = $dir | path join modules
    let backup = $dir | path join $BACKUP
    for f in [generations written.seen] { if ($backup | path join $f | path exists) { cp -p ($backup | path join $f) $dir } }
    let files = glob ($modules | path join **/*.nuon)
    let entries = $files | each {|f| open $f | get outputs | where kind in [file json ini] and ($it.hash? | default null) != null } | flatten
    $entries | sort-by { $in.at? | default 0 } | reduce --fold {} {|e, acc| $acc | upsert $e.target $e.hash }
    | items {|path, sum| $"($path)\t($sum)" } | str join "\n" | $"($in)\n" | save --force ($dir | path join written)
    for f in $files {
        let rec = open $f
        $rec | update outputs { where kind not-in [json ini] | each { reject --optional at } } | to nuon | save --force $f
    }
}

export def up []: nothing -> nothing { convert (state-dir) }
export def down []: nothing -> nothing { restore (state-dir) }
