#!/usr/bin/env -S nu --no-config-file

const PROPERTIES = [
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
    # a read-only /run/user still lets connect() through: systemd --user's private socket would start any command
    # outside the sandbox with network, and the ssh/gpg agents, session bus and wayland sit beside it
    InaccessiblePaths=-/run/dbus PrivateIPC=yes
]

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
    # BindPaths, not ReadWritePaths: under PrivateTmp a work dir in /tmp does not exist (226/NAMESPACE)
    # the runtime dir by path: systemd-run -p does not expand %t
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    let properties = $PROPERTIES | append [$"BindPaths=($work)" $"InaccessiblePaths=($runtime)"] | each { [-p $in] } | flatten
    (exec systemd-run --user --pty --wait --collect --quiet $"--unit=sandbox-build-($nu.pid)"
        $"--working-directory=($work)" ...$properties -- ...$command)
}
