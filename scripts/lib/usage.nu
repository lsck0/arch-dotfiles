use log.nu [log-err]

# the scripts dot.nu hands its commands to, which answer as dot
const DOT_HALVES = [dot-cli pipeline-cli]

# Logs "<command>: error: <message>" to stderr and exits 1, or 2 with --misuse.
export def die [message: string, --misuse]: nothing -> nothing {
    let stem = $env.CURRENT_FILE | path parse | get stem
    with-env {LOG_TAG: (if $stem in $DOT_HALVES { "dot" } else { $stem })} { log-err $message }
    exit (if $misuse { 2 } else { 1 })
}

# "1 file", "3 files": a count with its noun, which takes an s unless the count is one.
export def counted [count: int, noun: string]: nothing -> string {
    $"($count) ($noun)(if $count == 1 { '' } else { 's' })"
}

# Every `def "main ..."` in scope as {name, description, params}, name prefixed by prefix.
export def command-table [prefix: string = ""]: nothing -> table {
    scope commands | where name =~ '^main ' | each {|c|
        {
            name: ($c.name | str replace --regex '^main ' $prefix)
            description: ($c.description | lines | get --optional 0 | default "")
            params: ($c.signatures | values | first | where parameter_type not-in [input output] | select parameter_name parameter_type syntax_shape is_optional short_flag description completion)
        }
    }
}

# The switch or named flag of params that word (--name or -n) names, or null.
export def flag-find [params: table, word: string]: nothing -> any {
    let long = $word | parse --regex '^--(?<name>[^=]+)$' | get --optional 0.name
    let short = $word | parse --regex '^-(?<name>[^-])$' | get --optional 0.name
    $params | where parameter_type in [switch named] | where {|p| $p.parameter_name == $long or ($short != null and $p.short_flag == $short) } | get --optional 0
}

# What is wrong with dot's arguments, as one line, or null: an unknown flag or subcommand, a word too many, a missing
# one. dot-cli.nu and pipeline-cli.nu ask before nushell parses them against the signature and answers with its own
# frame. `open` names the commands that take any words.
export def words-misuse [table: table, words: list<string>, open: list<string>]: nothing -> any {
    let lead = $words | take while { not ($in | str starts-with "-") }
    let depth = seq 0 ($lead | length) | reverse | where {|n| ($lead | first $n | str join " ") in $table.name } | get --optional 0
    if $depth == null { return null }
    let name = $lead | first $depth | str join " "
    if $name in $open { return null }
    let params = $table | where name == $name | get 0.params
    let help = $"dot ($name) --help"
    mut given = []
    mut pending: any = null
    for word in ($words | skip $depth) {
        if $pending != null { $pending = null; continue }
        if $word in [--help -h] { return null }
        let typed = $word | parse --regex '^(?<flag>--[a-z][a-z0-9-]*|-[a-zA-Z])(?<value>=.*)?$' | get --optional 0
        if $typed == null { $given = $given | append $word; continue }
        let flag = flag-find $params $typed.flag
        if $flag == null { return $"dot ($name) has no flag ($typed.flag); ($help) lists them" }
        if $flag.parameter_type == named and ($typed.value | is-empty) { $pending = $typed.flag }
    }
    if $pending != null { return $"dot ($name): ($pending) needs a value; ($help) says which" }
    let positionals = $params | where parameter_type == positional
    let extra = if ($params | any { $in.parameter_type == rest }) { null } else { $given | get --optional ($positionals | length) }
    let missing = $positionals | where not is_optional | get --optional ($given | length)
    if $extra != null and ($table.name | any { $in | str starts-with $"($name) " }) {
        $"unknown command '($name) ($extra)'; ($help) lists them"
    } else if $extra != null {
        $"dot ($name) takes no '($extra)'; ($help) says what it takes"
    } else if $missing != null {
        $"dot ($name) needs <($missing.parameter_name)>; ($help) says what it takes"
    }
}

# The --help the words ask of a command in table, as nushell prints it for the script `dot`, or null. dot.nu hands
# the words to a script of another name, which nushell's own help would print in its place.
export def words-help [table: table, words: list<string>, open: list<string>]: nothing -> any {
    if not ($words | any { $in in [--help -h] }) { return null }
    let lead = $words | take while { not ($in | str starts-with "-") }
    let depth = seq 0 ($lead | length) | reverse | where {|n| ($lead | first $n | str join " ") in $table.name } | get --optional 0
    if $depth == null or $depth == 0 { return null }
    let name = $lead | first $depth | str join " "
    if $name in $open { return null }
    help $"main ($name)" | str replace $"> main ($name)" $"> dot ($name)"
}
