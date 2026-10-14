#!/usr/bin/env -S nu --no-config-file
# an untrusted build or test confined by systemd (a transient --user unit): no network, no new privileges, kernel knobs
# protected, the filesystem read-only except the work dir and a private /tmp; fetch dependencies first, the network is
# off by design. the work dir is a BindPaths= mount, not ReadWritePaths=: that only remounts an existing path, and
# under PrivateTmp= a work dir in /tmp does not exist inside the fresh /tmp (226/NAMESPACE); a bind carries it over

const PROPERTIES = [
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
]

# Run a command offline in the work dir, e.g. `sandbox-build -- cargo test` or `sandbox-build -w ./crate -- make`.
def --wrapped main [
    --work (-w): path  # the writable dir, $PWD without it
    ...command: string
]: nothing -> nothing {
    let command = if $command.0? == "--" { $command | skip 1 } else { $command }
    if ($command | is-empty) {
        print --stderr "usage: sandbox-build [-w writable-dir] [--] <command...>"
        exit 2
    }
    let work = $work | default $env.PWD | path expand
    let properties = $PROPERTIES | append $"BindPaths=($work)" | each { [-p $in] } | flatten
    (exec systemd-run --user --pty --wait --collect --quiet $"--unit=sandbox-build-($nu.pid)"
        $"--working-directory=($work)" ...$properties -- ...$command)
}
