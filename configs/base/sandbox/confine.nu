#!/usr/bin/env -S nu --no-config-file
# a GUI app in a transient systemd --user service with conservative hardening, defense in depth beside AppArmor (aa).
# a service, not a --scope: scopes take only resource-control properties and reject every exec sandboxing one. the
# Protect* knobs make the user manager imply PrivateUsers=, so supplementary groups show as nobody inside (devices go
# through logind's uaccess ACLs). no NoNewPrivileges: under NNP the kernel refuses every AppArmor exec transition to a
# profile that is not a subset of the current one, so apparmor.d profiles with cx/px children break (discord ->
# discord//crashpad_handler is denied "no new privs" and Discord dies on SIGTRAP); RestrictSUIDSGID covers setuid. no
# RestrictNamespaces/PrivateTmp/ProtectHome either: Chromium/Electron need user namespaces for their own sandbox and a
# shared /tmp and ~/.config. systemd-run --wait leaves the service running when it is killed, so it waits inside a
# scope the service is bound to: Ctrl-C, a timeout or a closed terminal ends the scope and with it the app

const SLICE = "confined.slice"
const PROPERTIES = [
    ProtectKernelTunables=yes ProtectKernelLogs=yes ProtectKernelModules=yes ProtectControlGroups=yes
    RestrictSUIDSGID=yes RestrictRealtime=yes LockPersonality=yes ProtectClock=yes
]

# Run a GUI app hardened, e.g. `confine -- discord`.
def --wrapped main [...command: string]: nothing -> nothing {
    let command = if $command.0? == "--" { $command | skip 1 } else { $command }
    if ($command | is-empty) {
        print --stderr "usage: confine [--] <command...>"
        exit 2
    }
    let unit = $"confine-($command.0 | path basename)-($nu.pid)"
    let scope = $"($unit)-caller.scope"
    let properties = $PROPERTIES ++ [$"BindsTo=($scope)" $"After=($scope)"] | each { [-p $in] } | flatten
    (exec systemd-run --user --scope --quiet $"--unit=($scope)" --
        systemd-run --user --pipe --wait --quiet --collect --same-dir $"--unit=($unit).service" $"--slice=($SLICE)"
        ...$properties -- ...$command)
}
