use module.nu *

const SYSCTL = "/etc/sysctl.d/99-hardening.conf"

# wsl runs microsoft's kernel, these keys do not exist there
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        # systemd-sysctl, not sysctl -p: only it expands the conf.* globs
        (file-copy sysctl-hardening.conf $SYSCTL --then [/usr/lib/systemd/systemd-sysctl $SYSCTL])
        # at the next modprobe; modules already loaded stay
        (file-copy modprobe-hardening.conf /etc/modprobe.d/hardening.conf)
    ]
}
