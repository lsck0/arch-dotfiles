use module.nu *

const SYSCTL = "/etc/sysctl.d/99-hardening.conf"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        # systemd-sysctl, not sysctl -p: only it expands the conf.* globs
        (file-copy sysctl-hardening.conf $SYSCTL --then [/usr/lib/systemd/systemd-sysctl $SYSCTL])
        (file-copy modprobe-hardening.conf /etc/modprobe.d/hardening.conf)
    ]
}
