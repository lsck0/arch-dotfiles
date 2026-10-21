#!/usr/bin/env -S nu --no-config-file

const SLICE = "confined.slice"
# no NoNewPrivileges (it denies apparmor cx/px transitions) or namespace, /tmp and home limits: electron needs them
const PROPERTIES = [
    ProtectKernelTunables=yes ProtectKernelLogs=yes ProtectKernelModules=yes ProtectControlGroups=yes
    RestrictSUIDSGID=yes RestrictRealtime=yes LockPersonality=yes ProtectClock=yes
]

# Run a GUI app hardened, e.g. `confine -- discord`.
def --wrapped main [...command: string]: nothing -> nothing {
    if ($command | get --optional 0) in ["-h" "--help"] { print "usage: confine [--] <command...>: run a GUI app hardened"; return }
    let command = if $command.0? == "--" { $command | skip 1 } else { $command }
    if ($command | is-empty) {
        print --stderr "usage: confine [--] <command...>"
        exit 2
    }
    let unit = $"confine-($command.0 | path basename)-($nu.pid)"
    let scope = $"($unit)-caller.scope"
    let properties = $PROPERTIES ++ [$"BindsTo=($scope)" $"After=($scope)"] | each { [-p $in] } | flatten
    # a service (scopes reject sandboxing) bound to a scope, since --wait alone survives ctrl-c
    (exec systemd-run --user --scope --quiet $"--unit=($scope)" --
        systemd-run --user --pipe --wait --quiet --collect --same-dir $"--unit=($unit).service" $"--slice=($SLICE)"
        ...$properties -- ...$command)
}
