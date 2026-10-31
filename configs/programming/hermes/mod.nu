use module.nu *
use ../../core/wallust/palette.nu *

# after caveman and rtk: the orchestrator profile is a one-time clone of ~/.hermes, which they fill with skills
export const meta = {
    deps: [programming/caveman programming/rtk desktop/idle-guards llm/vllm]
    packages: {pacman: [herdr-bin hermes-agent]}
    # the guard appears after planning on a fresh install; as an input it re-plans the hooks
    inputs: [~/.config/idle-guards/agent-guard.nu]
}

use ../../desktop/idle-guards/mod.nu [AGENT_GUARD]

const HOME = ".hermes"
const ORCHESTRATOR = "profiles/orchestrator"
const PYTHON = "/opt/hermes-agent/venv/bin/python"
const SKIN = "wallust"
const VLLM_BASE_URL = "http://127.0.0.1:8000/v1"
const VLLM_KEYS = [model_aliases.vllm providers.vllm]
const SETTINGS = {
    display.interface: tui
    model.default: claude-sonnet-5
    model.provider: anthropic
    delegation.provider: nous
    delegation.model: "meituan/longcat-2.0:free"
    fallback_providers: [
        {provider: nous, model: "meituan/longcat-2.0:free"}
        {provider: nous, model: "poolside/laguna-s-2.1:free"}
    ]
}
const ORCHESTRATOR_SETTINGS = {compression.threshold_tokens: 500000}
const ANTHROPIC_KEY_SECRET = "configs/secrets/keys/hermes-anthropic.env"
const REQUIRED_EXTRAS = [anthropic audio-io stt-whisper]
const GUARD_EVENTS = {
    pre_llm_call: turn-start
    post_llm_call: turn-end
    on_session_end: turn-end
    subagent_start: subagent-start
    subagent_stop: subagent-stop
}

def homes []: nothing -> record {
    let default = $nu.home-dir | path join $HOME
    {default: $default, orchestrator: ($default | path join $ORCHESTRATOR)}
}

# uv sync is a no-op once installed, so cheap on every apply
export def required-extras []: nothing -> nothing {
    ^hermes pm install ...($REQUIRED_EXTRAS | each {|e| [--extra $e] } | flatten)
}

def parse-env [path: path]: nothing -> record {
    if not ($path | path exists) { return {} }
    open --raw $path | lines | where ($it | str contains "=")
    | parse "{key}={value}" | reduce --fold {} {|row, acc| $acc | upsert ($row.key) $row.value }
}

def render-env [vars: record]: nothing -> string {
    $vars | items {|k, v| $"($k)=($v)" } | str join "\n" | $"($in)\n"
}

# merges the anthropic key secret into each home's own .env, never clobbering a key it does not own
def anthropic-key [home: path]: nothing -> list<record> {
    let secret = $env.DOTFILES | path join $ANTHROPIC_KEY_SECRET
    if not (secret-is-plaintext $secret) { return [] }
    let merged = (parse-env ($home | path join .env)) | merge (parse-env $secret)
    [(file-text ($home | path join .env) (render-env $merged) --mode 600)]
}

def configure [home: path, settings: record, remove: list<string>]: nothing -> list<record> {
    let guard = $nu.home-dir | path join $AGENT_GUARD
    let hooks = if ($guard | path exists) { $GUARD_EVENTS | items {|event, action| {$event: $"($guard) ($action)"} } | into record } else { {} }
    let want = {settings: $settings, remove: $remove, skin: $SKIN, hooks: $hooks}
    let have = try { open ($home | path join config.yaml) } catch { {} }
    let set = $settings | items {|key, value| ($have | get --optional ($key | split row "." | into cell-path)) == $value }
    let hooked = $hooks | items {|event, command| $command in ($have.hooks? | get --optional $event | default [] | get --optional command | default []) }
    let removed = $remove | each {|key| ($have | get --optional ($key | split row "." | into cell-path)) == null }
    let current = $set ++ $removed ++ $hooked ++ [($have.display?.skin? == $SKIN)] | all { $in }
    if $current { return [] }
    [(exec $"configure ($home)" [env $"HERMES_HOME=($home)" $PYTHON configure.py ($want | to json --raw)])]
}

# without a gpu share llm/vllm serves nothing, so hermes gets no vllm provider
def vllm-settings [vllm: any]: nothing -> record {
    if $vllm.gpu_memory_utilization? == null { return {} }
    {
        model_aliases.vllm: {model: $vllm.model, provider: custom, base_url: $VLLM_BASE_URL, api_key: null}
        providers.vllm: {base_url: $VLLM_BASE_URL, model: $vllm.model}
    }
}

export def link [cfg: record] {
    let h = homes
    let vllm = vllm-settings $cfg.deps?."llm/vllm"?
    let settings = $SETTINGS | merge $vllm
    let remove = if ($vllm | is-empty) { $VLLM_KEYS } else { [] }
    let skills = glob ($env.DOTFILES | path join skills "l-*") | where ($it | path type) == dir
    [
        (step required-extras --network)
        (exec orchestrator-create [
            hermes profile create orchestrator --clone --no-alias --description "Orchestrator. Not for interactive chat."
        ] --creates $h.orchestrator)
        (exec orchestrator-alias [hermes profile alias orchestrator --name hermes-orchestrator] --creates ($nu.home-dir | path join .local bin hermes-orchestrator))
        ($skills | each {|dir| file-link $dir ($h.orchestrator | path join skills ($dir | path basename)) })
        (configure $h.default $settings $remove)
        (configure $h.orchestrator ($settings | merge $ORCHESTRATOR_SETTINGS) $remove)
        (anthropic-key $h.default)
        (anthropic-key $h.orchestrator)
    ]
}

def skin []: nothing -> any {
    let slot = wal-load "hermes skin"
    if $slot == null { return null }
    let bg = do $slot background "#0b1019" | condition-bg
    let raw_fg = do $slot foreground "#c2c3c5"
    let accent = do $slot color4 "#B68B74" | vivify 0.45 0.55
    let alt = do $slot color5 "#A76495" | vivify 0.35 0.55
    let cool = do $slot color6 "#7dcfff" | vivify 0.35 0.55
    let status = $bg | shade 0.045
    let current = $bg | shade 0.11
    let fg = $raw_fg | readable-on $bg --ratio 7.0
    let dim = $fg | dim-toward $bg --ratio 2.6
    let urgent = $accent | semantic error $bg
    let good = $accent | semantic ok $bg
    let warn = $accent | semantic warn $bg
    let bad = mix $warn $urgent 0.5
    let added = mix $good [1.0 1.0 1.0] 0.88
    let removed = mix $urgent [1.0 1.0 1.0] 0.88
    let on = {|surface, colour, ratio| $colour | readable-on $surface --ratio $ratio | rgb-to-hex --prefix "#" }
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    let colors = [
        # no background key: the tui would paint it opaque through osc 11
        [banner_border (do $on $bg $accent 3.0)] [banner_title (do $on $bg $accent 4.5)]
        [banner_accent (do $on $bg $accent 4.5)] [banner_dim (do $hex $dim)] [banner_text (do $hex $fg)]
        [ui_accent (do $on $bg $accent 4.5)] [ui_label (do $on $bg $alt 4.5)] [ui_ok (do $on $bg $good 4.5)]
        [ui_error (do $on $bg $urgent 4.5)] [ui_warn (do $on $bg $warn 4.5)] [ui_tool (do $on $bg $accent 4.5)]
        [ui_thinking (do $hex $dim)]
        [diff_added (do $hex $added)] [diff_removed (do $hex $removed)]
        [diff_added_word (do $on $added $good 4.5)] [diff_removed_word (do $on $removed $urgent 4.5)]
        [syntax_string (do $on $bg $good 4.5)] [syntax_number (do $on $bg $cool 4.5)]
        [syntax_keyword (do $on $bg $accent 4.5)] [syntax_comment (do $hex $dim)] [prompt (do $hex $fg)]
        [input_rule (do $on $bg $accent 3.0)] [response_border (do $on $bg $accent 3.0)]
        [session_label (do $on $bg $alt 4.5)] [session_border (do $hex $dim)] [status_bar_bg (do $hex $status)]
        [status_bar_text (do $on $status $raw_fg 4.5)] [status_bar_strong (do $on $status $accent 4.5)]
        [status_bar_dim (do $on $status $raw_fg 2.4)] [status_bar_good (do $on $status $good 4.5)]
        [status_bar_warn (do $on $status $warn 4.5)] [status_bar_bad (do $on $status $bad 4.5)]
        [status_bar_critical (do $on $status $urgent 4.5)] [voice_status_bg (do $hex $status)]
        [selection_bg (do $hex $current)] [completion_menu_bg (do $hex $status)]
        [completion_menu_current_bg (do $hex $current)] [completion_menu_meta_bg (do $hex $status)]
        [completion_menu_meta_current_bg (do $hex $current)]
    ]
    [
        "# generated by configs/programming/hermes on every wallpaper switch, do not edit"
        $"name: ($SKIN)"
        'description: "Generated from the current wallpaper (wallust), do not hand-edit"'
        "colors:"
        ...($colors | each { $'  ($in.0): "($in.1)"' })
    ] | str join "\n" | $"($in)\n"
}

export def theme [cfg: record, wallpaper: string] {
    let skin = skin
    if $skin == null { return [] }
    homes | values | each {|home| file-text ($home | path join skins $"($SKIN).yaml") $skin --generated }
}
