use module.nu *

export const meta = {native_only: [system]}

const SYSCTL = "/etc/sysctl.d/99-hardening.conf"

export def system [cfg: record] {
    [
        # systemd-sysctl, not sysctl -p: only it expands the conf.* globs
        (file-copy config/sysctl-hardening.conf $SYSCTL --then [/usr/lib/systemd/systemd-sysctl $SYSCTL])
        (file-copy config/modprobe-hardening.conf /etc/modprobe.d/hardening.conf)
    ]
}
