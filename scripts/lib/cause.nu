# Why something failed, as data and as one line. A caught nushell error, or a command's exit code and output, becomes
# a cause: the command line, its exit code or that it is not installed and the package bringing it, the last stderr
# lines, where it ran. HINTS names the fix of each known failure class; FAILURES lines render, parse and group from it.

use commands.nu [COMMANDS_FILE commands-map-load OWNER_BASE OWNER_NONE]

const REPO = path self ../..
const STDERR_LINES = 3
const COMMAND_WIDTH_MAX = 100
const GROUP_SUBJECTS_SHOWN = 6
const GROUP_DETAILS_SHOWN = 6
# not anchored: a step's error can follow output that ended without a newline
const ERROR_HEAD = 'Error: nu::'
# error make's own code: its message is the module's, its location the raise site, not the cause
const ERROR_MADE = 'nu::shell::error'
const ERROR_AT = '\[(?<file>[^\]\s]+):(?<line>\d+):(?<col>\d+)\]'
const ERROR_MESSAGE = '^\s*(?:x|\x{d7}) (?<message>.*)$'
# a message wrapped at the renderer's width goes on in gutter lines without a line number
const ERROR_MESSAGE_MORE = '^\s*[|\x{2502}] (?<more>.*)$'
# the plain renderer's `-- and the fancy one's box drawing, which a tty gets (dot apply under script, pty-log)
const ERROR_LABEL = '(?:`--|\x{2570}\x{2500}\x{2500}) (?<label>.*)$'
const ERROR_GUTTER = '[|\x{2502}]'
const NOT_FOUND = 'Command `(?<name>[^`]+)` not found'
const EXITED = 'exited with code (?<code>-?\d+)'
# setsid's word for an argv[0] that is not on PATH
const EXEC_MISSING = 'failed to execute (?<name>\S+): No such file or directory'
# a call on its source line: words and quoted strings up to a pipe, a closing bracket, a statement's end or a comment
const CALL = r#'^(?<call>(?:"(?:[^"\\]|\\.)*"|'[^']*'|`[^`]*`|[^"'`|})\];#])*)'#
const SOURCES_UNNAMED = [source "<commandline>"]
const FIX_SEP = "; fix: "
const LINE_FORM = '^(?<head>.*?)(?:: (?<text>.*?))?(?:; fix: (?<fix>.*))?$'
const MODULE_HEAD = '^(?<subject>[\w.-]+/[\w./-]+) (?<where>\w+/.+)$'
const SYSTEM_SUBJECT = "system layer"
export const PACKAGES_FIX = "dot apply --packages"
export const SYSTEM_FIX = "dot apply --system"
# gets a fail-closed machine on an untrusted network online
export const ONLINE_ESCAPE = "dot set --machine base/networkmanager.untrusted_policy firewall-only && dot apply --system"

# The known failure classes, first match wins: pattern over a cause's text, label naming a group of them, each the
# placeholder a group's fix shows for <1>, fix with <1> the pattern's first capture.
export const HINTS = [
    [class pattern label each fix];
    [missing '(\S+) not installed (\([^)]*\))' "not installed" "" $PACKAGES_FIX]
    [timeout 'timed out after (\S+)' "timed out" "<bound>" "hung past its bound (<1>): dot log --trace shows the last output; a step that needs longer takes --timeout"]
    [refused 'returned error: (403|429)' "mirror refused" "" "the mirror refuses this address (<1>, a rate ban): wait, then dot apply --packages"]
    [dns '(?i)could not resolve(?: host)?|temporary failure in name resolution|name or service not known' "no DNS" "" $"no DNS, maybe the kill switch \(fw-egress\); to get online: ($ONLINE_ESCAPE)"]
    [not-found 'target not found: (\S+)' "pacman targets not found" "<package>" "no repo has <1>: the mirror adds a new name with its nightly build, else drop it from its module's packages"]
    [unsatisfied "unable to satisfy dependency '([^']+)'" "unsatisfiable dependencies" "<dependency>" "no repo has <1>: pin or drop the package needing it (l-dotfiles-add-package)"]
    [locked '\\0GITCRYPT|GITCRYPT|(?i)secrets? (?:are |is |stay |still )?locked' "secrets locked" "" "dot secrets unlock (YubiKey)"]
    [apparmor '(?i)apparmor="?denied' "apparmor denials" "" "journalctl -k -b -g 'apparmor=\"DENIED\"', then l-dotfiles-apparmor-profile"]
    [unit '(?i)job for (\S+) failed.*--user' "units failing to start" "<unit>" "journalctl --user -u <1> -b"]
    [unit '(?i)job for (\S+) failed|failed to start (\S+?):' "units failing to start" "<unit>" "journalctl -u <1> -b"]
    [root '(?i)permission denied|operation not permitted|must be run as root|run as root|a password is required|a terminal is required|incorrect password attempt|interactive authentication required' "needs root" "" $SYSTEM_FIX]
]

def repo-relative [file: string]: nothing -> string {
    if ($file | str starts-with $"($REPO)/") { $file | path relative-to $REPO } else { $file }
}

def command-short []: string -> string {
    let line = $in | str replace --all --regex '\s+' ' ' | str trim
    if ($line | str length) <= $COMMAND_WIDTH_MAX { $line } else { $"($line | str substring 0..<($COMMAND_WIDTH_MAX - 3))..." }
}

def message-join [message: any, label: any]: nothing -> any {
    if $message == null or ($label | is-empty) { return $message }
    $"($message | str trim --right --char '.'): ($label)"
}

# An argv as one shell-like line, a word with blanks or quotes single-quoted.
export def argv-text [argv: list<string>]: nothing -> string {
    $argv | each {|w| if $w =~ `[\s'"]` or ($w | is-empty) { $"'($w | str replace --all "'" "'\\''")'" } else { $w } } | str join " "
}

def message-unwrap [rows: list<string>]: nothing -> any {
    let first = $rows | enumerate | where item =~ $ERROR_MESSAGE | get --optional 0
    if $first == null { return null }
    let more = $rows | skip ($first.index + 1) | take while { $in =~ $ERROR_MESSAGE_MORE } | parse --regex $ERROR_MESSAGE_MORE | get more
    [($first.item | parse --regex $ERROR_MESSAGE | get 0.message)] ++ $more | each { str trim } | str join " "
}

# What a rendered nushell error says: the call on the line it points at, the command not found, the exit code, the
# file:line, its message, and whether error make raised it. Colour and either renderer's gutter are taken as they come.
def rendered-parse [colored: string]: nothing -> record {
    let rendered = $colored | ansi strip
    let rows = $rendered | lines
    let at = $rendered | parse --regex $ERROR_AT | where file not-in $SOURCES_UNNAMED | get --optional 0
    let code = if $at == null { null } else { $rows | parse --regex ('^\s*' + $at.line + ' ' + $ERROR_GUTTER + ' (?<code>.*)$') | get --optional 0.code }
    let call = if $code == null { null } else {
        $code | str substring ([(($at.col | into int) - 1) 0] | math max).. | parse --regex $CALL | get 0.call
        | str trim | str trim --left --char '^' | if ($in | is-empty) { null } else { $in }
    }
    {
        call: $call
        missing: ($rendered | parse --regex $NOT_FOUND | get --optional 0.name)
        exit_code: ($rendered | parse --regex $EXITED | get --optional 0.code | if $in == null { null } else { into int })
        at: (if $at == null { null } else { $"(repo-relative $at.file):($at.line)" })
        message: (message-unwrap $rows)
        label: ($rows | parse --regex $ERROR_LABEL | get --optional 0.label)
        made: ($rendered | str contains $ERROR_MADE)
    }
}

# The package that brings a command, from the commands map; null when the map knows none.
export def command-package [name: string]: nothing -> any {
    let keys = [$name $"/usr/bin/($name | path basename)" ($name | path basename)]
    let row = commands-map-load ($REPO | path join $COMMANDS_FILE) | transpose cmd row | where cmd in $keys | get --optional 0.row
    if $row == null or $row.owner in [$OWNER_BASE $OWNER_NONE] { null } else { $row.owner }
}

def cause-make [message: string, command: any, name: any, exit_code: any, stderr: list<string>, at: any]: nothing -> record {
    let missing = $name != null
    {
        message: $message
        command: $command
        name: $name
        exit_code: $exit_code
        missing: $missing
        package: (if $missing { command-package $name } else { null })
        stderr: $stderr
        at: $at
    }
}

# message: the error's own when there is one (the rendered one is wrapped at 80 columns), else the rendered or the
# fallback.
def from-rendered [found: record, message: any, fallback: string, command: any, exit_code: any, stderr: list<string>]: nothing -> record {
    # an error make's text may quote a cause already: it is the message, never parsed again
    let external = not $found.made and ($found.missing != null or $found.exit_code != null or $exit_code != null)
    let message = message-join ($message | default $found.message | default $fallback) $found.label
    if not $external {
        return (cause-make $message null null null $stderr (if $found.made { null } else { $found.at }))
    }
    let name = $found.missing
    let command = $found.call | default $name | default $command
    cause-make $message $command $name ($found.exit_code | default $exit_code) $stderr $found.at
}

# The cause of a caught nushell error ($e in a catch): an external call's command line, exit code or missing binary.
export def cause-from-error [err: record]: nothing -> record {
    from-rendered (rendered-parse ($err.rendered? | default "")) $err.msg $err.msg null $err.exit_code? []
}

# The cause of a command that exited non-zero with this output (stdout and stderr): a nushell error in it (a step)
# names the call inside, else the command itself; the stderr lines are the last before any error block.
export def cause-from-output [command: string, exit_code: int, output: string]: nothing -> record {
    let rows = $output | lines
    let head = $rows | enumerate | where item =~ $ERROR_HEAD | get --optional 0
    let split = if $head == null { null } else { $head.item | parse --regex $"^\(?<lead>.*?\)\(?<rest>($ERROR_HEAD).*\)$" | first }
    let before = if $head == null { $rows } else { ($rows | first $head.index) ++ [$split.lead] }
    let stderr = $before | where ($it | str trim) != "" | last $STDERR_LINES | each { str trim }
    if $head != null {
        let found = rendered-parse ([$split.rest] ++ ($rows | skip ($head.index + 1)) | str join "\n")
        return (from-rendered $found null $command $command null $stderr)
    }
    let missing = $output | parse --regex $EXEC_MISSING | get --optional 0.name
    cause-make $"($command) exited ($exit_code)" $command $missing $exit_code (if $missing == null { $stderr } else { [] }) null
}

# One line: "<name> not installed (<package>)", "`<command>` exited <code>: <stderr>" or the message, then (at
# <file:line>) when known.
export def cause-text [cause: record]: nothing -> string {
    let where = if $cause.at == null { "" } else { $" \(at ($cause.at)\)" }
    let stderr = if ($cause.stderr | is-empty) { "" } else { $": ($cause.stderr | str join ' / ')" }
    let text = if $cause.missing {
        $"($cause.name) not installed \(($cause.package | default 'no package known')\)"
    } else if $cause.exit_code != null and $cause.command != null {
        $"`($cause.command | command-short)` exited ($cause.exit_code)($stderr)"
    } else {
        $"($cause.message)($stderr)"
    }
    $"($text)($where)" | str replace --all --regex '\s*\n\s*' ' / '
}

# The first HINTS row matching text, <1> filled in: class, label, detail (the captures), fix and the group's fix.
export def cause-hint [text: string]: nothing -> any {
    for h in $HINTS {
        let m = $text | parse --regex $h.pattern | get --optional 0
        if $m == null { continue }
        let captures = $m | values | compact | where ($it | is-not-empty)
        let first = $captures | get --optional 0 | default ""
        return {
            class: $h.class
            label: $h.label
            detail: ($captures | str join " ")
            fix: ($h.fix | str replace --all "<1>" $first)
            fix_each: ($h.fix | str replace --all "<1>" $h.each)
        }
    }
    null
}

# "<subject>[ <where>]: <cause>[; fix: <fix>]" from a cause's text, the fix from HINTS unless --fix gives one. A
# module's where is "<verb>/<step>".
export def failure-line [subject: string, where: any, text: string, --fix: string]: nothing -> string {
    let fix = $fix | default (cause-hint $text | get --optional fix)
    let head = if ($where | is-empty) { $subject } else { $"($subject) ($where)" }
    $"($head): ($text)(if $fix == null { '' } else { $'($FIX_SEP)($fix)' })"
}

# A FAILURES line back into subject, where (null unless a module's), text and fix.
export def failure-parse [line: string]: nothing -> record {
    let p = $line | parse --regex $LINE_FORM | get 0
    let head = $p.head | parse --regex $MODULE_HEAD | get --optional 0
    {
        subject: ($head.subject? | default $p.head)
        where: $head.where?
        text: ($p.text | default "")
        fix: (if ($p.fix | is-empty) { null } else { $p.fix })
    }
}

# Whether a FAILURES line comes from the system layer: a module's system verb, or the layer's own line.
export def failure-is-system [line: string]: nothing -> bool {
    let p = failure-parse $line
    ($p.where | default "" | str starts-with "system/") or ($p.subject | str starts-with $SYSTEM_SUBJECT)
}

def shown [names: list<string>, count_max: int]: nothing -> string {
    let more = if ($names | length) > $count_max { $" +(($names | length) - $count_max) more" } else { "" }
    $"($names | first $count_max | str join ' ')($more)"
}

# FAILURES lines, one per cause: those of one failure class (or of one identical text) fold into one line naming
# their count and subjects, in the order each first failed; the system layer's own line, a wrapper, goes last.
export def failures-group [lines: list<string>]: nothing -> list<string> {
    let parsed = $lines | where ($it | str trim) != "" | uniq | enumerate | each {|l|
        let p = failure-parse $l.item
        let hint = cause-hint $p.text
        # modules group with modules, a phase (the secrets unlock) stands alone; a line without a cause with nothing
        let kind = if $p.where != null { "modules" } else { $p.subject }
        let key = if $hint != null { $"class ($hint.class) ($kind)" } else if ($p.text | is-empty) { $"line ($l.item)" } else { $"text ($p.text)($p.fix) ($kind)" }
        $p | merge {index: $l.index, line: $l.item, key: $key, hint: $hint, wrapper: ($p.subject | str starts-with $SYSTEM_SUBJECT)}
    }
    let groups = $parsed | group-by key | values | sort-by {|g| $g.0.index }
    ($groups | where {|g| not ($g | all { $in.wrapper }) }) ++ ($groups | where {|g| $g | all { $in.wrapper } }) | each {|g|
        if ($g | length) == 1 { return $g.0.line }
        let subjects = $g.subject | uniq
        let noun = if ($g | all { $in.where != null }) { "modules" } else { "failures" }
        let hint = $g.0.hint
        let text = if $hint == null { $g.0.text } else {
            let details = $g.hint.detail | where ($it | is-not-empty) | uniq
            if ($details | is-empty) { $hint.label } else { $"($hint.label): ($details | first $GROUP_DETAILS_SHOWN | str join ', ')(if ($details | length) > $GROUP_DETAILS_SHOWN { ', ...' } else { '' })" }
        }
        let fixes = $g.fix | compact | uniq
        let fix = if ($fixes | length) == 1 { $fixes.0 } else if $hint != null { $hint.fix_each } else { null }
        $"($g | length) ($noun) \((shown $subjects $GROUP_SUBJECTS_SHOWN)\): ($text)(if $fix == null { '' } else { $'($FIX_SEP)($fix)' })"
    }
}
