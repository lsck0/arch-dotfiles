#!/usr/bin/env -S nu --no-config-file

const PROPERTIES = [
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
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
    let properties = $PROPERTIES | append $"BindPaths=($work)" | each { [-p $in] } | flatten
    (exec systemd-run --user --pty --wait --collect --quiet $"--unit=sandbox-build-($nu.pid)"
        $"--working-directory=($work)" ...$properties -- ...$command)
}
