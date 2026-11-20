use module.nu *

export const meta = {packages: {native: [endlessh-git]}, volatile: true, deps: [base/ssh]}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy config /etc/endlessh/config)
        (dropin endlessh.service override.conf)
        # the declared port, not sshd -T: base/ssh writes the new one only after every module has planned
        (if $cfg.deps."base/ssh".port != 22 { unit-enable endlessh.service --now } else { unit-disable endlessh.service --now })
    ]
}
