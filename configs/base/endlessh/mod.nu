use module.nu *

export const meta = {packages: {native: [endlessh-git]}, volatile: true, deps: [base/ssh], native_only: [system]}

export def system [cfg: record] {
    let ssh = $cfg.deps."base/ssh"
    [
        (file-copy config/config /etc/endlessh/config)
        (dropin endlessh.service services/override.conf)
        # the declared port, not sshd -T: base/ssh writes the new one only after every module has planned
        (unit-switch endlessh.service ($ssh.server and $ssh.port != 22) --now)
    ]
}
