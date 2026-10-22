#!/usr/bin/env -S nu --no-config-file

const PROPERTIES = [
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
    # hidden, not read-only: connect() still reaches the bus, the agents, wayland and systemd --user's socket
    InaccessiblePaths=-/run/dbus PrivateIPC=yes
]

# ProtectHome=read-only still lets a build READ these and copy them into the work dir; hide them outright.
def sensitive-home-properties []: nothing -> list<string> {
    let secrets = $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles) | path join configs secrets
    [$"InaccessiblePaths=-($nu.home-dir | path join .ssh)" $"InaccessiblePaths=-($nu.home-dir | path join .gnupg)"
        $"InaccessiblePaths=-($nu.home-dir | path join sync)" $"InaccessiblePaths=-($secrets)"]
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
