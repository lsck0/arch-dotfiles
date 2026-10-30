#!/usr/bin/env -S nu --no-config-file

use ../../../scripts/lib/usage.nu [die]

const ENV_FILE = path self | path dirname | path join ../../secrets/keys/trmnl-claude.env | path expand
const PLUGIN_URL = "https://usetrmnl.com/api/custom_plugins"
const MESSAGES_URL = "https://api.anthropic.com/v1/messages"
const HTTP_TIMEOUT = 15sec
const POST_TIMEOUT = 30sec
const PUSH_STALE = 300min
const DAYS_SCANNED = 7
const SPARK_BLOCKS = [" " "\u{2581}" "\u{2582}" "\u{2583}" "\u{2584}" "\u{2585}" "\u{2586}" "\u{2587}" "\u{2588}"]
const MODEL_SLOTS = 3
const NONE = "\u{2014}"
const PROJECT_MARKERS = [github gitlab bitbucket repos projects]

const PRICING = {
    claude-fable-5-1: {input: 10.0, output: 50.0, cache_read: 0.25}
    claude-fable-5: {input: 10.0, output: 50.0, cache_read: 1.00}
    claude-opus-5-5: {input: 4.0, output: 20.0, cache_read: 0.20}
    claude-opus-5: {input: 5.0, output: 25.0, cache_read: 0.50}
    claude-opus-4-8: {input: 5.0, output: 25.0, cache_read: 0.50}
    claude-opus-4-7: {input: 5.0, output: 25.0, cache_read: 0.50}
    claude-opus-4-6: {input: 5.0, output: 25.0, cache_read: 0.50}
    claude-sonnet-5-5: {input: 2.0, output: 10.0, cache_read: 0.20}
    claude-sonnet-5: {input: 2.0, output: 10.0, cache_read: 0.20}
    claude-sonnet-4-6: {input: 3.0, output: 15.0, cache_read: 0.30}
    # a prompt over 100K tokens (input plus cache reads and writes) bills the whole message at the long rate
    claude-haiku-5-5: {
        input: 0.10, output: 0.50, cache_read: 0.01
        long: {above: 100_000, input: 0.50, output: 2.50, cache_read: 0.05}
    }
    claude-haiku-4-5: {input: 1.0, output: 5.0, cache_read: 0.10}
}
const PRICE_DEFAULT = {input: 3.0, output: 15.0, cache_read: 0.30}
const CACHE_WRITE_5M = 1.25
const CACHE_WRITE_1H = 2.0
# what a family's unlisted versions bill at
const FAMILY_PRICE = {fable: claude-fable-5, opus: claude-opus-5, sonnet: claude-sonnet-4-6, haiku: claude-haiku-4-5}
# letter boundaries only: "phi" must not hit claude-delphi, while versions run into names ("qwen3.8-max")
const ANTHROPIC = '(?<![a-z])(?:fable|opus|sonnet|haiku)(?![a-z])'
const FOREIGN = '(?<![a-z])(?:gpt|qwen|llama|gemini|mistral|deepseek|grok|kimi|glm|command-r|phi)(?![a-z])'
# a minor is one or two digits, so a date suffix is not one ("opus-5-20260101")
const FAMILY_VERSION = '(?<family>fable|opus|sonnet|haiku)(?:-?(?<major>\d{1,2})(?!\d)(?:[.-](?<minor>\d{1,2})\b)?)?'

def sum []: list<number> -> number { reduce --fold 0 {|x, acc| $acc + $x } }

def claude-dir []: nothing -> path {
    [($nu.home-dir | path join .claude) ($nu.home-dir | path join .config claude)] | where ($it | path exists)
    | get 0? | default ($nu.home-dir | path join .claude)
}

# push stamp under XDG state; only its mtime is read, to tell whether usage changed since the last post
def push-stamp []: nothing -> path {
    ($env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)) | path join trmnl-claude last-push
}

def tokens-format [n: int]: nothing -> string {
    if $n >= 1_000_000 { $"($n / 1_000_000 | into string --decimals 1)M" } else if $n >= 1_000 {
        $"($n / 1_000 | into string --decimals 0)K"
    } else { $n | into string }
}

def cost-format [c: float]: nothing -> string {
    if $c >= 100 {
        $"$($c | into string --decimals 0 | str replace --all --regex '\B(?=(\d{3})+$)' ',')"
    } else { $"$($c | into string --decimals (if $c >= 10 { 1 } else { 2 }))" }
}

# versioned: usage groups by key, so two keys under one name would list that name twice
def model-key [name: string]: nothing -> any {
    let n = $name | str lowercase
    let found = $n | parse --regex $FAMILY_VERSION | get 0?
    if $found != null {
        [claude $found.family $found.major $found.minor] | compact --empty | str join "-"
    } else if $n == "" or $n =~ '^[<_]' { null } else {
        $name
    }
}

def model-price [key: any]: nothing -> record {
    let family = $key | default "" | parse --regex '^claude-(?<family>fable|opus|sonnet|haiku)' | get 0?.family
    let fallback = if $family == null { $PRICE_DEFAULT } else { $PRICING | get ($FAMILY_PRICE | get $family) }
    $PRICING | get --optional ($key | default "") | default $fallback
}

def model-display [key: string]: nothing -> string {
    let parts = $key | split row "-" | where $it not-in ["" claude]
    if ($parts | is-empty) { return ($key | str substring 0..9) }
    let name = $parts.0 | str capitalize
    if $key =~ '^claude-(?:fable|opus|sonnet|haiku)' and ($parts | length) > 1 {
        $"($name) ($parts | skip 1 | str join '.')"
    } else { $name | str substring 0..9 }
}

def is-anthropic [key: string]: nothing -> bool {
    let n = $key | str lowercase
    ($n =~ $ANTHROPIC) or (not ($n =~ $FOREIGN) and ($n | str starts-with claude))
}

def project-name [encoded: string]: nothing -> string {
    let trimmed = $encoded | split row "--claude-worktrees-" | first
    let segments = $trimmed | split row "--" | last | split row "-"
    let marker = $segments | enumerate | where {|s|
        ($s.item | str lowercase) in $PROJECT_MARKERS and $s.index + 1 < ($segments | length)
    } | get 0?.index
    if $marker != null { $segments | skip ($marker + 1) | str join "-" } else { $segments | last 2 | str join "-" }
}

# Rows deduped by message and request id: every content block repeats its reply's usage, resumed sessions copy history.
def usage-rows [since: datetime]: nothing -> table {
    let bases = [(claude-dir | path join projects) ($nu.home-dir | path join .config claude projects)] | uniq
        | where ($it | path exists)
    let files = $bases | each {|b| glob ($b | path join "*" "*.jsonl") } | flatten
    if ($files | is-empty) { return [] }
    ls ...$files | where modified >= ($since - 1hr) | get name
    | each {|file|
        let project = project-name ($file | path dirname | path basename)
        open --raw $file | lines | where ($it | str contains '"assistant"')
        | each {|line| try { $line | from json } catch { null } }
        | where {|e| $e.type? == assistant and $e.timestamp? != null and $e.message?.usage? != null }
        | each {|e| usage-row $e ($file | path parse | get stem) $project $since }
    } | flatten | uniq-by id | where model != null
}

def usage-row [e: record, session: string, project: string, since: datetime]: nothing -> any {
    let ts = try { $e.timestamp | into datetime } catch { return null }
    if $ts < $since { return null }
    let u = $e.message.usage
    let input = $u.input_tokens? | default 0
    let output = $u.output_tokens? | default 0
    let read = $u.cache_read_input_tokens? | default 0
    let write = $u.cache_creation_input_tokens? | default 0
    let ttl = $u.cache_creation? | default {}
    let write_1h = $ttl.ephemeral_1h_input_tokens? | default 0
    let write_5m = $ttl.ephemeral_5m_input_tokens? | default (if ($ttl | is-empty) { $write } else { 0 })
    let model = model-key ($e.message.model? | default "")
    let base = model-price $model
    let p = if $base.long? != null and ($input + $read + $write) > $base.long.above { $base.long } else { $base }
    let cost = ($input * $p.input + $output * $p.output + $write_5m * $p.input * $CACHE_WRITE_5M
        + $write_1h * $p.input * $CACHE_WRITE_1H + $read * $p.cache_read)
    {
        id: (if $e.message.id? == null { $"uuid ($e.uuid?)" } else { $"($e.message.id) ($e.requestId?)" })
        day: ($ts | date to-timezone local | format date "%Y-%m-%d"), session: $session, project: $project
        model: $model, anthropic: ($model != null and (is-anthropic $model))
        input: $input, output: $output, cache_read: $read, cache_write: $write
        total: ($input + $output + $read + $write), cost: ($cost / 1_000_000)
    }
}

def credentials-read [claude: path]: nothing -> record {
    try {
        let oauth = open ($claude | path join .credentials.json) | get claudeAiOauth
        let tier = $oauth.rateLimitTier? | default "" | split row "_" | reverse | where $it =~ '^\d+x$' | get 0?
        let sub = $oauth.subscriptionType? | default unknown | str lowercase | str capitalize
        {sub: $sub, tier: ($tier | default standard)}
    } catch { {sub: Unknown, tier: $NONE} }
}

def sessions-active [claude: path]: nothing -> int {
    glob ($claude | path join sessions *.json)
    | where {|f|
        let pid = try { open $f | get pid } catch { null }
        $pid != null and ($"/proc/($pid)" | path exists)
    }
    | length
}

def reset-format [epoch: any]: nothing -> any {
    let t = try { $epoch | into int | $in * 1_000_000_000 | into datetime | date to-timezone local } catch {
        return null
    }
    let clock = $t | format date "%-I:%M%p" | str lowercase
    if ($t | format date "%F") == (date now | format date "%F") { $clock } else {
        $"($t | format date '%b %-d, ')($clock)"
    }
}

def usage-limits [claude: path]: nothing -> record {
    let token = try { open ($claude | path join .credentials.json) | get claudeAiOauth.accessToken } catch { null }
    if $token == null { return {} }
    let headers = {
        authorization: $"Bearer ($token)", anthropic-version: "2023-06-01", anthropic-beta: "oauth-2025-04-20"
    }
    let body = {model: claude-haiku-4-5, max_tokens: 1, messages: [{role: user, content: "."}]} | to json --raw
    let reply = try {
        http post --full --allow-errors --max-time $HTTP_TIMEOUT --headers $headers --content-type application/json (
            $MESSAGES_URL
        ) $body
    } catch { return {} }
    let found = $reply.headers.response | reduce --fold {} {|h, acc| $acc | upsert ($h.name | str lowercase) $h.value }
    [[key prefix]; [session 5h] [week_all 7d]] | reduce --fold {} {|w, acc|
        let header = {|field| $found | get --optional $"anthropic-ratelimit-unified-($w.prefix)-($field)" }
        let pct = try { do $header utilization | into float | $in * 100 | math round | into int } catch { null }
        if $pct == null { $acc } else { $acc | insert $w.key {pct: $pct, resets: (reset-format (do $header reset))} }
    }
}

def payload-build [include_other: bool, strict_activity: bool, scrape: bool]: nothing -> record {
    let claude = claude-dir
    let now = date now
    let today = $now | format date "%Y-%m-%d"
    let today_start = $now | format date "%Y-%m-%dT00:00:00%:z" | into datetime
    let rows = usage-rows ($today_start - ($DAYS_SCANNED * 1day))
    let counted = $rows | where { $include_other or $in.anthropic }
    let other = $rows | where { not $include_other and not $in.anthropic }
    let day_key = {|offset| $now - ($offset * 1day) | format date "%Y-%m-%d" }
    let day_total = {|day, wide|
        let mine = $counted | where day == $day | get total | sum
        if $wide { $mine + ($other | where day == $day | get total | sum) } else { $mine }
    }
    let wide = not $strict_activity
    let today_rows = $counted | where day == $today
    let today_total = $today_rows.total | sum
    let yesterday_total = do $day_total (do $day_key 1) false
    let trend = if $yesterday_total == 0 { "new" } else if $today_total > $yesterday_total * 1.1 { "up" } else if (
        $today_total < $yesterday_total * 0.9
    ) { "down" } else { "flat" }
    let week_start = $today_start - (($now | format date "%u" | into int) - 1) * 1day | format date "%Y-%m-%d"
    let week_rows = $counted | where day >= $week_start
    let spark_values = ($DAYS_SCANNED - 1)..0 | each {|i| do $day_total (do $day_key $i) $wide }
    let spark_max = if ($spark_values | any { $in > 0 }) { $spark_values | math max } else { 1 }
    let streak_from = if (do $day_total $today $wide) == 0 { 1 } else { 0 }
    let streak = $streak_from..$DAYS_SCANNED | each { $in }
        | take while {|i| (do $day_total (do $day_key $i) $wide) > 0 } | length
    let models = $counted | where day >= (do $day_key ($DAYS_SCANNED - 1)) | group-by model --to-table
        | each {|g| {key: $g.model, tokens: ($g.items.total | sum), cost: ($g.items.cost | sum)} }
        | sort-by tokens --reverse
    let model_tokens = $models.tokens | sum
    let projects = $counted | group-by project --to-table
        | each {|g| {name: $g.project, tokens: ($g.items.total | sum)} }
    let credentials = credentials-read $claude
    let limits = if $scrape { usage-limits $claude } else { {} }
    let slots = 0..<$MODEL_SLOTS | each {|i|
        let m = $models | get --optional $i
        let n = $i + 1
        if $m == null { {$"m($n)_name": "", $"m($n)_tokens": "", $"m($n)_pct": 0, $"m($n)_cost": ""} } else {
            {
                $"m($n)_name": (model-display $m.key), $"m($n)_tokens": (tokens-format $m.tokens)
                $"m($n)_pct": (if $model_tokens > 0 { $m.tokens / $model_tokens * 100 | into int } else { 0 })
                $"m($n)_cost": (cost-format $m.cost)
            }
        }
    }
    {
        sub: $credentials.sub, tier: $credentials.tier, active: (sessions-active $claude)
        t_input: (tokens-format ($today_rows.input | sum)), t_output: (tokens-format ($today_rows.output | sum))
        t_cache_r: (tokens-format ($today_rows.cache_read | sum))
        t_cache_w: (tokens-format ($today_rows.cache_write | sum))
        t_total: (tokens-format $today_total), t_cost: (cost-format ($today_rows.cost | sum | into float))
        t_sessions: ($today_rows.session | uniq | length), t_messages: ($today_rows | length), trend: $trend
        w_tokens: (tokens-format ($week_rows.total | sum)), w_cost: (cost-format ($week_rows.cost | sum | into float))
        w_sessions: ($week_rows.session | uniq | length), w_messages: ($week_rows | length)
        spark: ($spark_values | each {|v| $SPARK_BLOCKS | get ([8 ($v / $spark_max * 8 | into int)] | math min) }
            | str join)
        streak: $streak
        top_project: (if ($projects | is-empty) { $NONE } else {
            $projects | sort-by tokens --reverse | first | get name
        })
        u_session: ($limits.session?.pct? | default $NONE), u_week: ($limits.week_all?.pct? | default $NONE)
        u_reset: (if "session" in $limits { $limits.session.resets } else { "" })
        updated: ($now | format date "%b %-d, %H:%M")
    } | merge ($slots | reduce --fold {} {|s, acc| $acc | merge $s })
}

def payload-sample []: nothing -> record {
    {
        sub: Max, tier: 20x, active: 2, t_input: 1.2M, t_output: 245K, t_cache_r: 3.4M, t_cache_w: 890K
        t_total: 5.7M, t_cost: "$18.50", t_sessions: 4, t_messages: 142, trend: up, w_tokens: 28.3M, w_cost: "$67.89"
        w_sessions: 12, w_messages: 847, spark: ([1 3 5 7 4 6 8 5] | each {|i| $SPARK_BLOCKS | get $i } | str join)
        streak: 7, top_project: trmnl-claude, updated: "Apr 4, 11:22"
        m1_name: "Opus 5.5", m1_tokens: 18.2M, m1_pct: 64, m1_cost: "$312", m2_name: "Sonnet 5", m2_tokens: 8.1M
        m2_pct: 29, m2_cost: "$24.30", m3_name: "Haiku 4.5", m3_tokens: 2.0M, m3_pct: 7, m3_cost: "$1.60"
        u_session: 42, u_week: 18, u_reset: "3:00pm"
    }
}

# The uuid is the plugin's write credential: it stays in this process, never in an argv.
def plugin-post [payload: record]: nothing -> nothing {
    let from_file = if ($ENV_FILE | path exists) { open --raw $ENV_FILE | lines | parse "{key}={value}" } else { [] }
    let uuid = $env.TRMNL_PLUGIN_UUID? | default ($from_file | where key == TRMNL_PLUGIN_UUID | get 0?.value)
    if $uuid == null { error make {msg: $"missing ($ENV_FILE) \(TRMNL_PLUGIN_UUID=...\)"} }
    let body = {merge_variables: $payload} | to json --raw
    let reply = http post --full --allow-errors --raw --max-time $POST_TIMEOUT --content-type application/json (
        $"($PLUGIN_URL)/($uuid)"
    ) $body
    let answer = $reply.body | default "" | str trim
    if $reply.status >= 200 and $reply.status < 300 { print $"OK \(($reply.status)\): ($answer)" } else {
        print --stderr $"HTTP ($reply.status): ($answer)"
        exit 1
    }
    let stamp = push-stamp
    mkdir ($stamp | path dirname)
    touch $stamp
}

# Post this machine's Claude Code usage to the TRMNL plugin (--dry-run prints the payload instead).
def main [
    --dry-run                # print the payload json, post nothing
    --test                   # sample data, to preview the layouts
    --no-scrape              # leave out the rate-limit bars (no api call)
    --include-other-models   # count gateway models in the totals, cost and breakdown
    --strict-activity        # only anthropic models in the streak and sparkline
]: nothing -> nothing {
    if $include_other_models and $strict_activity {
        die --misuse "--include-other-models and --strict-activity exclude each other"
    }
    $env.LC_TIME = "C"
    let payload = if $test { payload-sample } else {
        payload-build $include_other_models $strict_activity (not $no_scrape)
    }
    if $dry_run { print ($payload | to json --indent 2) } else { plugin-post $payload }
}

# The timer's ExecCondition: exit 0 to post (claude was used since, or the posted data is stale), 1 to skip.
# systemd reads any 1-254 from ExecCondition as a clean skip, so an uncaught error (which nu exits 1 for)
# would silently stop all posting; a genuine failure exits 255 instead, which systemd counts as failed.
def "main changed" []: nothing -> nothing {
    let code = try {
        let claude = claude-dir
        let pushed = push-stamp
        if not ($pushed | path exists) { 0 } else {
            let at = ls $pushed | get 0.modified
            if $at < ((date now) - $PUSH_STALE) or ($at | format date "%F") != (date now | format date "%F") {
                0
            } else {
                let dirs = [projects sessions] | each {|d| $claude | path join $d } | where ($it | path exists)
                let files = $dirs | each {|d| glob ($d | path join "**" "*") } | flatten
                if ($files | is-not-empty) and (ls --all --directory ...$files | any { $in.modified > $at }) { 0 } else { 1 }
            }
        }
    } catch {|e|
        print --stderr $"trmnl-claude changed: ($e.msg)"
        255
    }
    exit $code
}
