# the lsck0 iso's second stage, run from the verified checkout its stub fetched (mirror/iso/.../lsck0-install hands
# over through bootstrap.sh with LSCK0_INSTALL=1, online already): the answer file and the lsck0.* boot parameters,
# checked against bootstrap/questions.nuon, become the bootstrap's BOOTSTRAP_* env, then dot internal bootstrap runs.
# The stub reads wifi, keymap and source itself; here they are only validated.

use log.nu *

const DOT = path self ../dot.nu
const QUESTIONS = path self bootstrap/questions.nuon
const ANSWERS_NAME = "lsck0.nuon"
const ANSWERS_LABEL = "/dev/disk/by-label/LSCK0"
const BOOT_MEDIUM = "/run/archiso/bootmnt"
const STAGE_DIR = "/run/lsck0"
const ISO_GLOB = "archlinux-lsck0*.iso"
const ISO_SEARCH_DEPTH = 2
const CMDLINE_PARAM = '(?:^|\s)lsck0\.(?<key>[^\s=]+)=(?:"(?<quoted>[^"]*)"|(?<plain>\S*))'
const MEDIA_FSTYPES = [vfat exfat iso9660 udf ntfs ntfs3]
const FETCH_TIMEOUT_S = 5
const PASSWORD_ASK = "ask"
const PASSWORD_HASH = '^\$(1|2[aby]|5|6|y|gy|7)\$'
const LOG = "/tmp/lsck0-install.log"
# a question's kind as the answer file's type
const KIND_TYPES = {
    text: string password: string flag: bool menu: string keymap: string profile: string platform: string
    groups: "list<string>" disk: string
}

# -----------------------------------------------------------------------------
# answers
# -----------------------------------------------------------------------------

# answer-file key: {type, env (the BOOTSTRAP_* it sets), keys (a record's own), password}
export def answers-spec [questions: record]: nothing -> record {
    let asked = $questions.questions | where {|e| $e.id? != null } | each {|e|
        {id: $e.id, type: ($KIND_TYPES | get $e.kind), env: $e.env, keys: null, password: ($e.kind == "password")}
    }
    let own = $questions.answers | each {|a| {id: $a.id, type: $a.type, env: ($a.env? | default ""), keys: $a.keys?, password: false} }
    $asked ++ $own | uniq-by id | reduce --fold {} {|k, acc| $acc | insert $k.id ($k | reject id) }
}

def type-of [value: any]: nothing -> string {
    let t = $value | describe
    if ($t | str starts-with "record") { return record }
    if ($t | str starts-with "list") or ($t | str starts-with "table") {
        if ($value | all {|v| ($v | describe) == "string" }) { return "list<string>" }
        if ($value | all {|v| ($v | describe) | str starts-with "record" }) { return "list<record>" }
    }
    $t
}

def record-problems [r: record, spec: record, prefix: string]: nothing -> list<string> {
    $r | items {|k, v|
        if $k not-in $spec {
            $"($prefix)($k): unknown key, one of ($spec | columns | str join ' ')"
        } else if (type-of $v) != ($spec | get $k) and not (($spec | get $k) == "list<string>" and ($v | is-empty)) {
            $"($prefix)($k): expected ($spec | get $k), got (type-of $v)"
        }
    } | compact
}

export def answers-problems [spec: record, a: record]: nothing -> list<string> {
    let top = record-problems $a ($spec | items {|k, v| {k: $k, type: $v.type} } | reduce --fold {} {|it, acc| $acc | insert $it.k $it.type }) ""
    if ($top | is-not-empty) { return $top }
    let wifi = $a.wifi? | default [] | enumerate | each {|w|
        let p = record-problems $w.item $spec.wifi.keys $"wifi.($w.index)."
        if ($w.item.ssid? | is-empty) { $p | append $"wifi.($w.index).ssid: missing" } else { $p }
    } | flatten
    let source = if $a.source? == null { [] } else {
        let p = record-problems $a.source $spec.source.keys "source."
        if ($a.source.bundle? | is-empty) { $p | append "source.bundle: missing" } else { $p }
    }
    let hashed = $spec | items {|k, v| if $v.password { $k } } | compact | where {|k| ($a | get --optional $k | default "") =~ $PASSWORD_HASH }
        | each {|k| $"($k): a crypt hash, the bootstrap takes the password itself or \"ask\"" }
    $wifi ++ $source ++ $hashed
}

def cmdline-value [spec: record, key: string, raw: string]: nothing -> any {
    let leaf = $key | split row "." | last
    let type = if ($key | str starts-with "wifi.") { $spec.wifi.keys | get --optional $leaf } else if ($key | str starts-with "source.") { $spec.source.keys | get --optional $leaf } else { $spec | get --optional $key | get --optional type }
    match $type {
        "bool" => (match ($raw | str lowercase) { "1" | "true" | "yes" => true, "0" | "false" | "no" => false, _ => $raw })
        "list<string>" => ($raw | split row "," | where $it != "")
        _ => $raw
    }
}

# lsck0.answers=<url or path>, lsck0.<key>=<value>; wifi.ssid/wifi.psk set the first network
export def answers-cmdline [spec: record, cmdline: string]: nothing -> record {
    $cmdline | parse --regex $CMDLINE_PARAM | reduce --fold {answers: null, overrides: {}} {|p, acc|
        let raw = if ($p.quoted | is-not-empty) { $p.quoted } else { $p.plain }
        if $p.key == "answers" { return ($acc | update answers $raw) }
        let path = if ($p.key | str starts-with "wifi.") { $p.key | str replace "wifi." "wifi.0." } else { $p.key }
        let cells = $path | split row "." | each {|c| if $c =~ '^\d+$' { $c | into int } else { $c } } | into cell-path
        let overrides = if ($p.key | str starts-with "wifi.") and ($acc.overrides.wifi? == null) { $acc.overrides | insert wifi [{}] } else { $acc.overrides }
        $acc | update overrides ($overrides | upsert $cells (cmdline-value $spec $p.key $raw))
    }
}

def answers-parse [text: string, origin: string]: nothing -> record {
    let a = try { $text | from nuon } catch {|e| error make {msg: $"($origin): not nuon: ($e.msg)"} }
    if ($a | describe | str starts-with "record") { $a } else { error make {msg: $"($origin): expected a record"} }
}

def answers-in [dir: path]: nothing -> list<path> {
    let beside = glob --depth $ISO_SEARCH_DEPTH ($dir | path join "**" $ISO_GLOB) | each { path dirname | path join $ANSWERS_NAME }
    [($dir | path join $ANSWERS_NAME)] ++ $beside | uniq | where { path exists }
}

# the stub's copy when it found one; else the boot medium, the LSCK0 partition, then every other medium
def answers-media []: nothing -> any {
    let handed = $env.LSCK0_ANSWERS? | default ""
    if $handed != "" { return (answers-parse (open --raw $handed) ($env.LSCK0_ANSWERS_ORIGIN? | default $handed) | insert origin ($env.LSCK0_ANSWERS_ORIGIN? | default $handed)) }
    for f in (answers-in $BOOT_MEDIUM) { return (answers-parse (open --raw $f) $f | insert origin $f) }
    let devices = ^lsblk -J -l -pno NAME,FSTYPE,MOUNTPOINT | from json | get blockdevices | where fstype in $MEDIA_FSTYPES
    let label = if ($ANSWERS_LABEL | path exists) { $ANSWERS_LABEL | path expand } else { "" }
    for d in (($devices | where name == $label) ++ ($devices | where name != $label)) {
        let mounted = $d.mountpoint | is-not-empty
        let dir = if $mounted { $d.mountpoint } else { $STAGE_DIR | path join mnt ($d.name | path basename) }
        if not $mounted {
            mkdir $dir
            if (^mount -o ro $d.name $dir | complete).exit_code != 0 { continue }
        }
        let found = answers-in $dir | get --optional 0
        let a = if $found == null { null } else {
            let origin = $"($d.name):($found | path relative-to $dir)"
            try { answers-parse (open --raw $found) $origin | insert origin $origin } catch {|e| {error: $e.msg} }
        }
        if not $mounted { ^umount $dir | complete | ignore }
        if $a.error? != null { error make {msg: $a.error} }
        if $a != null { return $a }
    }
    null
}

def answers-fetch [where: string]: nothing -> record {
    if $where =~ '^https?://' {
        let r = ^curl -fsS -m $FETCH_TIMEOUT_S $where | complete
        if $r.exit_code != 0 { error make {msg: $"($where): ($r.stderr | str trim)"} }
        return (answers-parse $r.stdout $where)
    }
    let file = if ($where | str starts-with "/") { $where } else { $BOOT_MEDIUM | path join $where }
    if not ($file | path exists) { error make {msg: $"($where): no such file"} }
    answers-parse (open --raw $file) $where
}

export def answers-env [spec: record, a: record]: nothing -> record {
    $a | items {|k, v|
        let key = $spec | get --optional $k | default {env: "", password: false}
        if $key.env == "" or ($key.password and $v == $PASSWORD_ASK) { return null }
        let text = match (type-of $v) { "bool" => (if $v { "1" } else { "0" }), "list<string>" => ($v | str join " "), _ => $v }
        {$key.env: $text}
    } | compact | reduce --fold {} {|it, acc| $acc | merge $it }
}

def answers-or-die [spec: record, a: record]: nothing -> record {
    let problems = answers-problems $spec $a
    if ($problems | is-not-empty) { error make {msg: $"answers: ($problems | str join '; '), nothing installed"} }
    $a
}

# -----------------------------------------------------------------------------
# install
# -----------------------------------------------------------------------------

export def iso-install-run []: nothing -> nothing {
    $env.LOG_TAG = "install"
    let spec = answers-spec (open $QUESTIONS)
    let cmdline = answers-cmdline $spec (open --raw /proc/cmdline)
    let media = answers-media
    let fetched = if $cmdline.answers == null { {} } else { answers-fetch $cmdline.answers }
    let answers = answers-or-die $spec (($media | default {} | reject --optional origin) | merge deep $fetched | merge deep $cmdline.overrides)
    let origins = [$media.origin? $cmdline.answers] | compact
    log-info $"second stage from (^git -C ($DOT | path dirname | path dirname) rev-parse --short HEAD | str trim), answers from (if ($origins | is-empty) { 'nowhere, every question is asked' } else { $origins | str join ' and ' })"
    let unattended = $answers.unattended? | default false
    let status = with-env (answers-env $spec $answers) {
        let argv = [$nu.current-exe --no-config-file $DOT internal bootstrap]
        # unattended runs keep a log; the dialog screens of an interactive one would garble it
        try {
            if $unattended { ^bash -o pipefail -c $'"$@" 2>&1 | tee ($LOG)' iso-install ...$argv } else { run-external ...$argv }
            0
        } catch { $env.LAST_EXIT_CODE }
    }
    if $status != 0 { error make {msg: $"the bootstrap failed \(exit ($status)\)(if $unattended { $', log in ($LOG)' } else { '' })"} }
}
