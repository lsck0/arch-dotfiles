#!/usr/bin/env -S nu --no-config-file

const PROPERTIES = [
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
    # hidden, not read-only: connect() still reaches the bus, the agents, wayland and systemd --user's socket
    InaccessiblePaths=-/run/dbus PrivateIPC=yes
]

# home paths holding keys, tokens and browser or messenger sessions, relative to $HOME
const SENSITIVE_HOME = [
    .ssh .gnupg .pgpass .netrc .kube .aws .docker .claude .codex .gemini .copilot .hermes .password-store sync
    .age .rage
    .config/gh .config/rclone .config/dotfiles .config/age .config/containers/auth.json
    .local/share/keyrings .local/share/password-store .local/share/kwalletd .local/share/pgpass
    .local/share/mozilla .local/share/librewolf .local/share/zen .local/share/qutebrowser .local/share/TelegramDesktop
    .config/chromium .config/discord .config/Signal
]

# ProtectHome=read-only still lets a build READ these and copy them into the work dir; hide them outright.
def sensitive-home-properties []: nothing -> list<string> {
    let repo = $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)
    # the git-crypt symmetric key decrypts every secret; the module copy lives under .git, the submodule's under .git/modules
    let repo_secrets = [
        ($repo | path join configs secrets)
        ($repo | path join .git git-crypt)
        ($repo | path join .git modules configs secrets git-crypt)
    ]
    $SENSITIVE_HOME | each {|p| $nu.home-dir | path join $p } | append $repo_secrets
    | each { $"InaccessiblePaths=-($in)" }
}

# Run a command offline in the work dir, e.g. `sandbox-build -- cargo test` or `sandbox-build -w ./crate -- make`.
def --wrapped main [
    --work (-w): path  # the writable dir, $PWD without it
    ...command: string
]: nothing -> nothing {
    if ($command | get --optional 0) in ["-h" "--help"] { print "usage: sandbox-build [-w writable-dir] [--] <command...>: run it offline in the work dir"; return }
    let command = if $command.0? == "--" { $command | skip 1 } else { $command }
    if ($command | is-empty) {
        print --stderr "usage: sandbox-build [-w writable-dir] [--] <command...>"
        exit 2
    }
    let work = $work | default $env.PWD | path expand
    # by path: systemd-run -p does not expand %t
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    # BindPaths, not ReadWritePaths: a /tmp work dir is missing under PrivateTmp (226/NAMESPACE)
    let git = $work | path join .git
    let properties = $PROPERTIES | append [$"BindPaths=($work)" $"InaccessiblePaths=($runtime)"]
        | append (sensitive-home-properties)
        | append (if ($git | path exists) { [$"ReadOnlyPaths=($git)"] } else { [] })
        | each { [-p $in] } | flatten
    (exec systemd-run --user --pty --wait --collect --quiet $"--unit=sandbox-build-($nu.pid)"
        $"--working-directory=($work)" ...$properties -- ...$command)
}
