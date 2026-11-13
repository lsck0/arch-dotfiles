use module.nu *
use ../../core/wallust/palette.nu *
use ../../desktop/idle-guards/mod.nu [AGENT_GUARD AGENT_GUARD_INPUT guard-hook]
use ../../desktop/hyprland/mod.nu [reload]
use ../../llm/ollama/ollama-ensure-models.nu [LONG_CONTEXT]

# after caveman and rtk: the orchestrator profile is a one-time clone of ~/.hermes, which they fill with skills
export const meta = {
    deps: [programming/caveman programming/rtk desktop/idle-guards llm/vllm llm/ollama]
    packages: {pacman: [herdr-bin hermes-agent hermes-agent-desktop]}
    # the guard appears after planning on a fresh install; as an input it re-plans the hooks. The MCP servers every
    # module's mcp-servers merged: one written after this module ran reaches hermes on its next apply
    inputs: [$AGENT_GUARD_INPUT ~/.hermes/mcp-servers.json]
}

export const options = {
    system_agent: {
        type: bool
        default: false
        doc: "An always-on Hermes session (profile system, unit hermes-system-agent) that drives the desktop and talks: SUPER+grave shows it, SUPER+ALT+a talks to it"
        label: "System agent"
        scope: machine
    }
}

const HOME = ".hermes"
const ORCHESTRATOR = "profiles/orchestrator"
const SYSTEM = "profiles/system"
const SYSTEM_UNIT = "hermes-system-agent.service"
# voice in both directions: the local whisper for speech in, piper's local voice reading every answer aloud; ctrl+space
# toggles recording (the SUPER+ALT+a bind sends it to the tmux pane), barge-in stops it when Luca talks over it
const SYSTEM_SETTINGS = {
    voice.auto_tts: true
    tts.provider: piper
    tts.piper.voice: "en_US-lessac-medium"
    stt.provider: local
    stt.language: ""
    stt.local.model: small
}
const PYTHON = "/opt/hermes-agent/venv/bin/python"
const SKIN = "wallust"
const VLLM_BASE_URL = "http://127.0.0.1:8000/v1"
const VLLM_KEYS = [model_aliases.vllm providers.vllm]
# ollama's openai endpoint; its proxy socket is the 11434 every client uses
const OLLAMA_BASE_URL = "http://127.0.0.1:11434/v1"
const OLLAMA_KEYS = [model_aliases.ollama providers.ollama]
const SETTINGS = {
    display.interface: tui
    model.default: claude-sonnet-5
    model.provider: anthropic
    delegation.provider: anthropic
    delegation.model: claude-sonnet-5
    # the tui has no hold-to-talk, only a start/stop toggle key
    voice.record_key: "ctrl+space"
    fallback_providers: [
        {provider: nous, model: "meituan/longcat-2.0:free"}
        {provider: nous, model: "poolside/laguna-s-2.1:free"}
    ]
}
const ORCHESTRATOR_SETTINGS = {compression.threshold_tokens: 500000}
const ANTHROPIC_KEY_SECRET = "configs/secrets/keys/hermes-anthropic.env"
const REQUIRED_EXTRAS = [anthropic audio-io stt-whisper piper]
# rewritten by every hermes-agent package update, which may need a venv sync
const HERMES_LOCK = "/opt/hermes-agent/uv.lock"
const GUARD_EVENTS = {
    pre_llm_call: turn-start
    post_llm_call: turn-end
    on_session_end: turn-end
    subagent_start: subagent-start
    subagent_stop: subagent-stop
}

def homes []: nothing -> record {
    let default = $nu.home-dir | path join $HOME
    {default: $default, orchestrator: ($default | path join $ORCHESTRATOR), system: ($default | path join $SYSTEM)}
}

# A profile cloned from ~/.hermes with the skills, settings and key. Its command goes through the hermes on PATH:
# hermes' own `profile alias` bakes in the venv path of the install it ran under, which the next hermes update removes.
def profile [
    name: string, description: string, settings: record, remove: list<string>, mcp: record, skills: list<path>
]: nothing -> list<record> {
    let home = homes | get $name
    [
        (exec $"($name)-create" [hermes profile create $name --clone --no-alias --description $description] --creates $home)
        (file-text ($nu.home-dir | path join .local bin $"hermes-($name)") $"#!/bin/sh\nexec hermes -p ($name) \"$@\"\n" --mode "755")
        ($skills | each {|dir| file-link $dir ($home | path join skills ($dir | path basename)) })
        (configure $home $settings $remove $mcp)
        (anthropic-key $home)
    ]
}

# The system agent's profile, voice, unit and hyprland binds, only where the option is on.
def system-agent [settings: record, remove: list<string>, mcp: record, skills: list<path>]: nothing -> list<record> {
    [
        (profile system "System agent: always on, drives the desktop, talks." ($settings | merge $SYSTEM_SETTINGS) $remove $mcp $skills)
        (file-link system-agent.sh ($nu.home-dir | path join .local bin hermes-system-agent))
        (unit-file $SYSTEM_UNIT --enable --now)
        (file-copy hypr-system-agent.lua ($nu.home-dir | path join .config hypr dropins system_agent.lua) --then (then-step hypr-reload))
    ]
}

# a package update rewrites the lock, which may need a sync; the step still checks the receipt itself
def extras-key []: nothing -> string {
    let lock = try { open --raw $HERMES_LOCK | hash sha256 } catch { "" }
    [$lock ...$REQUIRED_EXTRAS] | str join " "
}

# uv sync is a no-op once installed, but pm refuses to get there on a packaged install: once ~/.hermes/tools/facts.json
# exists (its first sync writes it), it counts the package's system-store tools as not installed. So it runs only when
# the last sync receipt lacks an extra or predates the package's uv.lock.
export def required-extras []: nothing -> nothing {
    # before the first sync it prints prose, which `from json` reads as a string
    let parsed = try { ^hermes pm status | from json } catch { {} }
    let receipt = if ($parsed | describe | str starts-with record) { $parsed } else { {} }
    let features = $receipt.feature_list? | default []
    let fresh = try { ($receipt.finished_at | into datetime) > (ls $HERMES_LOCK | get 0.modified) } catch { false }
    if $receipt.outcome? == ok and ($REQUIRED_EXTRAS | all {|e| $e in $features }) and $fresh { return }
    ^hermes pm install ...($REQUIRED_EXTRAS | each {|e| [--extra $e] } | flatten)
}

# merges the anthropic key secret into each home's own .env, never clobbering a key it does not own
def anthropic-key [home: path]: nothing -> list<record> {
    let secret = $env.DOTFILES | path join $ANTHROPIC_KEY_SECRET
    if not (secret-is-plaintext $secret) { return [] }
    let file = $home | path join .env
    let merged = env-file-load $file | merge (env-file-load $secret) | items {|k, v| $"($k)=($v)" } | str join "\n"
    [(file-text $file $"($merged)\n" --mode 600)]
}

def configure [home: path, settings: record, remove: list<string>, mcp: record]: nothing -> list<record> {
    let guard = $nu.home-dir | path join $AGENT_GUARD
    let hooks = if ($guard | path exists) { $GUARD_EVENTS | items {|event, action| {$event: $"($guard) ($action)"} } | into record } else { {} }
    let want = {settings: $settings, remove: $remove, skin: $SKIN, hooks: $hooks, mcp: $mcp}
    let have = try { open ($home | path join config.yaml) } catch { {} }
    let set = $settings | items {|key, value| ($have | get --optional ($key | split row "." | into cell-path)) == $value }
    let hooked = $hooks | items {|event, command| $command in ($have.hooks? | get --optional $event | default [] | get --optional command | default []) }
    # a guard hook left from when the guard existed keeps hermes calling a deleted script
    let stale = $have.hooks? | default {} | values | compact | flatten
        | any {|h| ($h | guard-hook) and $h.command? not-in ($hooks | values) }
    let removed = $remove | each {|key| ($have | get --optional ($key | split row "." | into cell-path)) == null }
    let served = $mcp | items {|name, spec| ($have.mcp_servers? | get --optional $name) == $spec }
    let current = $set ++ $removed ++ $hooked ++ $served ++ [($have.display?.skin? == $SKIN) (not $stale)] | all { $in }
    [(exec $"configure ($home)" [env $"HERMES_HOME=($home)" $PYTHON configure.py ($want | to json --raw)] --done=$current)]
}

# without a gpu share llm/vllm serves nothing, so hermes gets no vllm provider
def vllm-settings [vllm: any]: nothing -> record {
    if $vllm.gpu_memory_utilization? == null { return {} }
    {
        model_aliases.vllm: {model: $vllm.model, provider: custom, base_url: $VLLM_BASE_URL, api_key: null}
        providers.vllm: {base_url: $VLLM_BASE_URL, model: $vllm.model}
    }
}

# llm/ollama pulls its uncensored models only where a gpu runs them; hermes offers the long-context one there
def ollama-settings [ollama: any]: nothing -> record {
    if $ollama == null or (gpu-list | where vram > 0b | is-empty) { return {} }
    {
        model_aliases.ollama: {model: $LONG_CONTEXT, provider: custom, base_url: $OLLAMA_BASE_URL, api_key: null}
        providers.ollama: {base_url: $OLLAMA_BASE_URL, model: $LONG_CONTEXT}
    }
}

export def link [cfg: record] {
    let vllm = vllm-settings $cfg.deps?."llm/vllm"?
    let ollama = ollama-settings $cfg.deps?."llm/ollama"?
    let settings = $SETTINGS | merge $vllm | merge $ollama
    let remove = (if ($vllm | is-empty) { $VLLM_KEYS } else { [] }) ++ (if ($ollama | is-empty) { $OLLAMA_KEYS } else { [] })
    let skills = glob ($env.DOTFILES | path join skills "l-*") | where ($it | path type) == dir
    let home = homes | get default
    let mcp = try { open ($home | path join mcp-servers.json) } catch { {} }
    [
        (step required-extras --key (extras-key) --network)
        (profile orchestrator "Orchestrator. Not for interactive chat." ($settings | merge $ORCHESTRATOR_SETTINGS) $remove $mcp $skills)
        (configure $home $settings $remove $mcp)
        (anthropic-key $home)
        (if $cfg.system_agent { system-agent $settings $remove $mcp $skills })
    ]
}

def skin []: nothing -> any {
    let p = palette-rgb "hermes skin"
    if $p == null { return null }
    let bg = $p.bg | condition-bg
    let raw_fg = $p.fg
    let accent = $p.c4 | vivify 0.45 0.55
    let alt = $p.c5 | vivify 0.35 0.55
    let cool = $p.c6 | vivify 0.35 0.55
    let status = $bg | shade $SHADE_CHROME
    let current = $bg | shade $SHADE_CURRENT
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
    ] | to text
}

export def theme [cfg: record, wallpaper: string] {
    let skin = skin
    if $skin == null { return [] }
    homes | values | where ($it | path exists) | each {|home| file-text ($home | path join skins $"($SKIN).yaml") $skin --generated }
}

# desktop/hyprland's reload: skipped without a session (the install's config stage), and keeps the shader
export def hypr-reload []: nothing -> nothing { reload }
