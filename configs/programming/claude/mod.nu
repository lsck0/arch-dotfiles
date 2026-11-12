use module.nu *
use ../../desktop/idle-guards/mod.nu [AGENT_GUARD AGENT_GUARD_INPUT guard-hook]

# after idle-guards: the guard hooks go in only once its agent-guard exists (a dep outside the platform's groups is dropped)
export const meta = {
    deps: [desktop/idle-guards]
    packages: {pacman: [claude-code claude-desktop-extra]}
    backup: {secrets: true}
    # planned before idle-guards runs on a fresh install: the guard appearing re-plans the hooks
    inputs: [$AGENT_GUARD_INPUT]
}

export const options = {
    model: {type: string, default: "claude-opus-5-5", doc: "The model every session starts on", label: "Model", scope: user}
    effort: {
        type: string
        default: medium
        doc: "Reasoning effort of that model"
        label: "Effort"
        choices: [low medium high xhigh max]
        scope: user
    }
}

const ACCOUNT_KEYS = [oauthAccount userID hasCompletedOnboarding lastOnboardingVersion]

def home [...parts: string]: nothing -> path {
    $nu.home-dir | path join ...$parts
}

# Per machine: it holds credentials, so a new machine logs in itself instead of being seeded.
def backup-dir []: nothing -> path {
    host-file ($env.DOTFILES | path join configs secrets keys claude)
}

# A granted permission prompt resumes the turn without a new prompt, so every tool call re-arms the guard.
const GUARD_EVENTS = {
    UserPromptSubmit: turn-start PreToolUse: turn-start PostToolUse: turn-start Stop: turn-end StopFailure: turn-end
    SessionEnd: turn-end Notification: turn-end SubagentStart: subagent-start SubagentStop: subagent-stop
}
const NOTIFICATION_MATCHER = "idle_prompt|permission_prompt|agent_needs_input|elicitation_dialog"

def guard-hooks [guard: path]: nothing -> record {
    $GUARD_EVENTS | items {|event, action|
        let entry = {hooks: [{type: command, command: $"($guard) ($action)"}]}
        {$event: [(if $event == Notification { {matcher: $NOTIFICATION_MATCHER} | merge $entry } else { $entry })]}
    } | into record
}

# Every event's entries others put there, then the guard's while it exists; an event left empty is dropped.
def hooks-merge [current: record, guard: path]: nothing -> record {
    let wanted = if ($guard | path exists) { guard-hooks $guard } else { {} }
    $current | columns | append ($wanted | columns) | uniq | each {|event|
        let entries = $current | get --optional $event | default []
            | where { not ($in | guard-hook) }
            | append ($wanted | get --optional $event | default [])
        if ($entries | is-empty) { null } else { {$event: $entries} }
    } | into record
}

export def link [cfg: record] {
    let settings = home .claude settings.json
    let current = try { open $settings | get --optional hooks | default {} } catch { {} }
    let creds = home .claude .credentials.json
    let backup = backup-dir
    [
        (shell-aliases claude)
        (files-into (home .claude) CLAUDE.md RTK.md keybindings.json)
        (json-merge $settings [
            (json-set [remoteControlAtStartup] true)
            (json-set [model] $cfg.model)
            (json-set [voice] {enabled: true, mode: hold})
            # remote control needs feature flags, which the session-wide DO_NOT_TRACK switches off
            (json-set [env DO_NOT_TRACK] "0")
            (json-set [env DISABLE_ERROR_REPORTING] "1")
            (json-set [env CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY] "1")
            (json-set [attribution] {commit: "", pr: ""})
            (json-set [modelSettings $cfg.model effortLevel] $cfg.effort)
            (json-set [hooks] (hooks-merge $current (home $AGENT_GUARD)))
            # login via credentials.json only: settings.json is shared into every identity
            (json-delete [env CLAUDE_CODE_OAUTH_TOKEN])
        ])
        (if (secret-is-plaintext ($backup | path join credentials.json)) and not ($creds | path exists) {
            [
                (exec claude-login [install -Dm600 ($backup | path join credentials.json) $creds] --creates $creds)
                (json-merge (home .claude.json) (open ($backup | path join account.json) | items {|k, v| json-set [$k] $v }))
            ]
        })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    # light-ansi paints panels (diffs, user messages) in ansi white, which light palettes keep as a mid-grey text
    # colour (github-light's color7 is #6e7781), so the panels come out dark: light takes Claude's own rgb theme
    json-merge (home .claude settings.json) [(json-set [theme] (if $p.light == "1" { "light" } else { "dark-ansi" }))]
}

export def backup [cfg: record]: nothing -> nothing {
    let creds = home .claude .credentials.json
    if not ($creds | path exists) {
        error make {msg: $"no ($creds), run claude and log in first"}
    }
    if not (secret-is-plaintext ($env.DOTFILES | path join configs secrets keys pgp_privatekey.asc)) {
        error make {msg: "secrets is locked, unlock it first"}
    }
    let dir = backup-dir
    mkdir $dir
    ^install -m600 $creds ($dir | path join credentials.json)
    open (home .claude.json) | select --optional ...$ACCOUNT_KEYS | to json --indent 2 | $"($in)\n" | save --force ($dir | path join account.json)
}
