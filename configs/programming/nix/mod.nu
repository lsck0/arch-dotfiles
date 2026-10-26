use module.nu *

export const meta = {packages: {pacman: [nix], nix: [nixfmt]}}

const DAEMON = "/usr/lib/systemd/system/nix-daemon.service"
const RESTART = "systemctl daemon-reload && systemctl try-restart nix-daemon.service"

export def link [cfg: record] {
    file-copy nix.conf (xdg config nix nix.conf)
}

export def system [cfg: record] {
    if not ($DAEMON | path exists) { return [] }
    # KillMode=process: a restart spares running builds; it reloads first, the engine does only after the module
    file-copy 10-priority.conf (unit-dir | path join nix-daemon.service.d 10-priority.conf) --then [sh -c $RESTART]
}
