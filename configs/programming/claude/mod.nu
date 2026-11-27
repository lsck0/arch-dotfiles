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
    voice: {type: bool, default: true, doc: "Voice dictation, hold to talk", label: "Voice", scope: user}
    remote_control: {
        type: bool
        default: false
        doc: "Every session registers with the remote-control relay at start. It needs Claude's feature flags, so on, DO_NOT_TRACK is lifted for claude and usage telemetry is sent; off, telemetry is off"
        label: "Remote control"
    }
}

# Credentials no agent tool reads (the Read, Grep and Glob tools; a module's own code and `secret-is-plaintext` in a
# shell still do). Paths only where the value is the whole file: ~/.claude, ~/.hermes and ~/sync stay readable.
const SECRET_READS_REPO = ["configs/secrets/keys/**" ".git/git-crypt/**" ".git/modules/**/git-crypt/**"]
const SECRET_READS_HOME = [
    ".ssh/id_*" ".gnupg/**" ".config/sops/age/**" ".config/gh/**" ".config/rclone/**" ".config/containers/auth.json"
    ".docker/config.json" ".config/git/forgejo-credentials" ".config/tea/config.yml" ".config/sccache/config"
    ".config/task/sync.taskrc" ".config/task/calendar.env" ".config/obs-studio/basic/profiles/*/service.json"
    ".netrc" ".pgpass" ".local/share/pgpass" ".claude/.credentials.json" ".hermes/.env" ".hermes/**/.env"
]

const ACCOUNT_KEYS = [oauthAccount userID hasCompletedOnboarding lastOnboardingVersion]

def home [...parts: string]: nothing -> path {
    $nu.home-dir | path join ...$parts
}

# Per machine: it holds credentials, so a new machine logs in itself instead of being seeded.
def backup-dir []: nothing -> path {
    host-file (secret-path keys claude)
}

# `//` is an absolute path in a permission rule, `~/` the home dir.
def secret-reads-deny []: nothing -> list<string> {
    let repo = $SECRET_READS_REPO | each {|glob| $"Read\(/($env.DOTFILES | path join $glob)\)" }
    $repo ++ ($SECRET_READS_HOME | each {|glob| $"Read\(~/($glob)\)" })
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
    let restore = (secret-is-plaintext ($backup | path join credentials.json)) and not ($creds | path exists)
    [
        # the wrapper that drops the session's DO_NOT_TRACK, only where remote control wants the feature flags
        (if $cfg.remote_control { shell-aliases claude })
        (files-into (home .claude) config/CLAUDE.md config/RTK.md config/keybindings.json)
        (json-merge $settings [
            (json-set [remoteControlAtStartup] $cfg.remote_control)
            (json-set [model] $cfg.model)
            (json-set [voice] {enabled: $cfg.voice, mode: hold})
            ...(if $cfg.remote_control {
                # remote control needs feature flags, which the session-wide DO_NOT_TRACK and DISABLE_TELEMETRY switch off
                [(json-set [env DO_NOT_TRACK] "0") (json-delete [env DISABLE_TELEMETRY])]
            } else {
                [(json-delete [env DO_NOT_TRACK]) (json-set [env DISABLE_TELEMETRY] "1")]
            })
            (json-set [permissions deny] (secret-reads-deny))
            (json-set [env DISABLE_ERROR_REPORTING] "1")
            (json-set [env CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY] "1")
            (json-set [attribution] {commit: "", pr: ""})
            # ~80 l-* skills overflow the default 1% of the context, and the listing drops their descriptions
            (json-set [skillListingBudgetFraction] 0.04)
            (json-set [modelSettings $cfg.model effortLevel] $cfg.effort)
            (json-set [hooks] (hooks-merge $current (home $AGENT_GUARD)))
            # login via credentials.json only: settings.json is shared into every identity
            (json-delete [env CLAUDE_CODE_OAUTH_TOKEN])
        ])
        (if $restore { exec claude-login [install -Dm600 ($backup | path join credentials.json) $creds] --creates $creds })
        (account-merge $restore $backup)
    ]
}

# Declared on every run with the value already there, the backup's only while restoring a login: keys declared only
# while the credentials are missing are dropped, and so deleted, by the next run, which sees them present.
def account-merge [restore: bool, backup: path]: nothing -> any {
    let file = home .claude.json
    let current = try { open $file | select --optional ...$ACCOUNT_KEYS } catch { {} }
    let saved = if $restore { open ($backup | path join account.json) } else { {} }
    let account = $current | merge $saved
    let keys = $ACCOUNT_KEYS | where {|k| ($account | get --optional $k) != null }
    if ($keys | is-empty) { return null }
    json-merge $file ($keys | each {|k| {$k: ($account | get $k)} } | into record)
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    # the ansi themes paint panels (diffs, user messages) in a palette slot meant as text: light-ansi in white, a mid-grey
    # on light palettes (github-light's color7 is #6e7781), dark-ansi in bright black, a mid-grey under light text on
    # dark ones (color8 #75777E): both take Claude's own rgb theme
    json-merge (home .claude settings.json) [(json-set [theme] (if $p.light == "1" { "light" } else { "dark" }))]
}

export def backup [cfg: record]: nothing -> nothing {
    let creds = home .claude .credentials.json
    if not ($creds | path exists) {
        error make {msg: $"no ($creds), run claude and log in first"}
    }
    let dir = backup-dir
    mkdir $dir
    ^install -m600 $creds ($dir | path join credentials.json)
    open (home .claude.json) | select --optional ...$ACCOUNT_KEYS | to json --indent 2 | $"($in)\n" | save --force ($dir | path join account.json)
}
