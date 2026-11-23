use module.nu *

export const meta = {packages: {native: [endlessh-git]}, volatile: true, deps: [base/ssh], native_only: [system]}

export def system [cfg: record] {
    [
        (file-copy config /etc/endlessh/config)
        (dropin endlessh.service override.conf)
        # the declared port, not sshd -T: base/ssh writes the new one only after every module has planned
        (unit-switch endlessh.service ($cfg.deps."base/ssh".port != 22) --now)
    ]
}
