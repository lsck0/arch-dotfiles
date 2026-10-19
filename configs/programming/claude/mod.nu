use module.nu *

export const meta = {packages: {pacman: [claude-code claude-desktop-extra]}, backup: {secrets: true}}

export const options = {
    model: {type: string, default: "claude-opus-5-5", doc: "The model every session starts on", label: "Model"}
    effort: {
        type: string
        default: medium
        doc: "Reasoning effort of that model"
        label: "Effort"
        choices: [low medium high xhigh max]
    }
}

const GUARD = ".config/idle-guards/agent-guard.nu"
const ACCOUNT_KEYS = [oauthAccount userID hasCompletedOnboarding lastOnboardingVersion]
const TOKEN_CONF = "environment.d/50-claude-oauth-token.conf"
const PRIVATE = "600"

def home [...parts: string]: nothing -> path {
    $nu.home-dir | path join ...$parts
}

def backup-dir []: nothing -> path {
    $env.DOTFILES | path join secrets claude
}

# a granted permission prompt resumes the turn without a new prompt, so every tool call re-arms the guard
def guard-hooks [guard: path]: nothing -> record {
    let hook = {|action| [{hooks: [{type: command, command: $"($guard) ($action)"}]}] }
    let start = do $hook turn-start
    let end = do $hook turn-end
    {
        UserPromptSubmit: $start PreToolUse: $start PostToolUse: $start Stop: $end StopFailure: $end SessionEnd: $end
        Notification: [{matcher: "idle_prompt|permission_prompt|agent_needs_input|elicitation_dialog", hooks: $end.0.hooks}]
        SubagentStart: (do $hook subagent-start) SubagentStop: (do $hook subagent-stop)
    }
}

def hooks-merge [current: record, guard: path]: nothing -> record {
    let own = {|entry| $entry.hooks? | default [] | any {|h| $h.command? | default "" | str contains agent-guard } }
    let kept = $current | items {|event, entries| {event: $event, entries: ($entries | where {|e| not (do $own $e) })} }
        | where ($it.entries | is-not-empty) | reduce --fold {} {|e, acc| $acc | insert $e.event $e.entries }
    let wanted = if ($guard | path exists) { guard-hooks $guard } else { {} }
    $wanted | items {|event, entries| {event: $event, entries: $entries} }
        | reduce --fold $kept {|e, acc| $acc | upsert $e.event (($acc | get --optional $e.event | default []) ++ $e.entries) }
}

export def link [cfg: record] {
    let settings = home .claude settings.json
    let current = if ($settings | path exists) { open $settings | get --optional hooks | default {} } else { {} }
    let creds = home .claude .credentials.json
    let token = $env.DOTFILES | path join secrets claude-oauth-token
    # remote control needs feature flags, which the session-wide DO_NOT_TRACK switches off
    [
        (files-into (home .claude) CLAUDE.md RTK.md keybindings.json)
        (json-merge $settings [
            (json-set [remoteControlAtStartup] true)
            (json-set [model] $cfg.model)
            (json-set [voice] {enabled: true, mode: hold})
            (json-set [env DO_NOT_TRACK] "0")
            (json-set [env DISABLE_ERROR_REPORTING] "1")
            (json-set [env CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY] "1")
            (json-set [modelSettings $cfg.model effortLevel] $cfg.effort)
            (json-set [hooks] (hooks-merge $current (home $GUARD)))
        ])
        (if (secret-is-plaintext (backup-dir | path join credentials.json)) and not ($creds | path exists) {
            [
                (exec claude-login [install -Dm600 (backup-dir | path join credentials.json) $creds] --creates $creds)
                (json-merge (home .claude.json) (open (backup-dir | path join account.json) | items {|k, v| json-set [$k] $v }))
            ]
        } else { [] })
        (if (secret-is-plaintext $token) {
            file-text (home .config $TOKEN_CONF) $"CLAUDE_CODE_OAUTH_TOKEN=(open --raw $token | str trim)\n" --mode $PRIVATE
        } else { [] })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    json-merge (home .claude settings.json) [(json-set [theme] (if $p.light == "1" { "light-ansi" } else { "dark-ansi" }))]
}

export def backup [cfg: record]: nothing -> nothing {
    let creds = home .claude .credentials.json
    if not ($creds | path exists) {
        error make {msg: $"no ($creds), run claude and log in first"}
    }
    if not (secret-is-plaintext ($env.DOTFILES | path join secrets pgp_privatekey.asc)) {
        error make {msg: "secrets is locked, unlock it first"}
    }
    mkdir (backup-dir)
    ^install -m600 $creds (backup-dir | path join credentials.json)
    open (home .claude.json) | select --optional ...$ACCOUNT_KEYS | to json --indent 2 | $"($in)\n" | save --force (backup-dir | path join account.json)
}
