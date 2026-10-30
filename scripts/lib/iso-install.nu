# The iso's second stage: answer file and lsck0.* params become BOOTSTRAP_* for the bootstrap.

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
const PLATFORM_DEFAULT = "custom"
const KIND_TYPES = {
    text: string password: string flag: bool menu: string keymap: string profile: string platform: string
    groups: "list<string>" disk: string
}

# Answer-file keys from the questions: {type, env (the BOOTSTRAP_* it sets), keys (a record's own), password}.
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

# Type errors in answers a against spec, plus missing wifi ssids and source bundles and crypt-hashed passwords.
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

const STUB_PARAMS = [insecure]

# The lsck0.* kernel parameters: lsck0.answers=<url or path> and overrides, wifi.* setting the first network.
export def answers-cmdline [spec: record, cmdline: string]: nothing -> record {
    $cmdline | parse --regex $CMDLINE_PARAM | reduce --fold {answers: null, overrides: {}} {|p, acc|
        let raw = if ($p.quoted | is-not-empty) { $p.quoted } else { $p.plain }
        if $p.key == "answers" { return ($acc | update answers $raw) }
        # read by the stub alone (accepting an unsigned answers source), no answer
        if $p.key in $STUB_PARAMS { return $acc }
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

def answers-media []: nothing -> any {
    let handed = $env.LSCK0_ANSWERS? | default ""
    if $handed != "" {
        # a malformed handed file falls back to interactive, as in the stub, instead of aborting the second stage
        let origin = $env.LSCK0_ANSWERS_ORIGIN? | default $handed
        let parsed = try { answers-parse (open --raw $handed) $origin | insert origin $origin } catch {|e| log-warn $"($e.msg), continuing interactively"; null }
        if $parsed != null { return $parsed }
    }
    for f in (answers-in $BOOT_MEDIUM) {
        let parsed = try { answers-parse (open --raw $f) $f | insert origin $f } catch {|e| log-warn $"($e.msg), ignoring it"; null }
        if $parsed != null { return $parsed }
    }
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
        # a broken answer file on an unrelated scanned device is not fatal: skip it and keep looking
        if $a.error? != null { log-warn $"ignoring unparseable answer file on ($d.name): ($a.error)"; continue }
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

# The answers as BOOTSTRAP_* variables; an "ask" password is left for the bootstrap to prompt.
export def answers-env [spec: record, a: record]: nothing -> record {
    $a | items {|k, v|
        let key = $spec | get --optional $k | default {env: "", password: false}
        if $key.env == "" or ($key.password and $v == $PASSWORD_ASK) { return null }
        let text = match (type-of $v) { "bool" => (if $v { "1" } else { "0" }), "list<string>" => ($v | str join " "), _ => $v }
        {$key.env: $text}
    } | compact | reduce --fold {} {|it, acc| $acc | merge $it }
}

def when-holds [when: any, c: record]: nothing -> bool {
    $when | default {} | items {|field, want|
        if $field not-in $c { return true }
        let have = $c | get $field
        if ($want | describe | str starts-with "list") { $have in $want } else { $have == $want }
    } | all {|held| $held }
}

# Answered keys whose every question is skipped for this machine; passwords are left out, always read.
export def answers-unused [questions: record, a: record]: nothing -> list<string> {
    let platform = $a.platform? | default $PLATFORM_DEFAULT | if $in == $PLATFORM_DEFAULT and ($a.server? | default false) { "server" } else { $in }
    let c = $a | merge {
        platform: $platform, encrypt: ($a.encrypt? | default true), host_wsl: false, machine_wsl: false
        password_given: ($a.password? | default "" | is-not-empty)
    }
    let asked = $questions.questions | where {|e| $e.id? != null and $e.kind != "password" }
    $a | columns | where {|k| $k in $asked.id } | where {|k| not ($asked | where id == $k | any {|e| when-holds $e.when? $c }) }
}

def answers-ask [questions: record, a: record]: nothing -> record {
    let asks = $questions.questions | where {|e| $e.kind? == "password" } | get id | uniq | where {|k| ($a | get --optional $k) == $PASSWORD_ASK }
    if ($asks | is-empty) { return $a }
    if not (is-terminal --stdin) { error make {msg: $"answers: ($asks | str join ', ') \"($PASSWORD_ASK)\" with unattended, and no console to ask on"} }
    $asks | reduce --fold $a {|k, acc|
        let entries = $questions.questions | where {|e| $e.id? == $k }
        let e = $entries | first
        let title = $e.title | str replace --all "{username}" ($acc.username? | default "user")
        let empty_ok = $entries | any {|e| $e.empty_ok? | default false }
        mut typed = ""
        loop {
            print -e $e.text
            let first = input -s $"($title): "
            print -e ""
            if ($first | is-empty) and not $empty_ok { print -e $questions.messages.password_empty; continue }
            let second = input -s $questions.messages.password_again_plain
            print -e ""
            if $first == $second { $typed = $first; break }
            print -e $questions.messages.password_mismatch
        }
        $acc | upsert $k $typed
    }
}

def answers-or-die [spec: record, a: record]: nothing -> record {
    let problems = answers-problems $spec $a
    if ($problems | is-not-empty) { error make {msg: $"answers: ($problems | str join '; '), nothing installed"} }
    $a
}

export def iso-install-run []: nothing -> nothing {
    $env.LOG_TAG = "install"
    let questions = open $QUESTIONS
    let spec = answers-spec $questions
    let cmdline = answers-cmdline $spec (open --raw /proc/cmdline)
    let media = answers-media
    let fetched = if $cmdline.answers == null { {} } else { answers-fetch $cmdline.answers }
    let answers = answers-or-die $spec (($media | default {} | reject --optional origin) | merge deep $fetched | merge deep $cmdline.overrides)
    let origins = [$media.origin? $cmdline.answers] | compact
    log-info $"second stage from (^git -C ($DOT | path dirname | path dirname) rev-parse --short HEAD | str trim), answers from (if ($origins | is-empty) { 'nowhere, every question is asked' } else { $origins | str join ' and ' })"
    for k in (answers-unused $questions $answers) {
        log-warn $"answers: ($k) is not asked for this platform, its value is ignored"
    }
    let unattended = $answers.unattended? | default false
    let answers = if $unattended { answers-ask $questions $answers } else { $answers }
    let status = with-env (answers-env $spec $answers | insert LSCK0_LOG (if $unattended { $LOG } else { "" })) {
        let argv = [$nu.current-exe --no-config-file $DOT internal bootstrap]
        try {
            if $unattended { ^bash -o pipefail -c $'"$@" 2>&1 | tee ($LOG)' iso-install ...$argv } else { run-external ...$argv }
            0
        } catch { $env.LAST_EXIT_CODE }
    }
    if $status != 0 { error make {msg: $"the bootstrap failed \(exit ($status)\)(if $unattended { $', log in ($LOG)' } else { '' })"} }
}
