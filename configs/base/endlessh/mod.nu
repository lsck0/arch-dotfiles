use module.nu *

export const meta = {packages: {native: [endlessh-git]}, volatile: true, deps: [base/ssh]}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy config /etc/endlessh/config)
        (dropin endlessh.service override.conf)
        (if not (^sshd -T o+e>| complete | get stdout | lines | any { ($in | str lowercase) == "port 22" }) {
            unit-enable endlessh.service --now
        })
    ]
}
