use module.nu *

# systemd-native sandboxes: sandbox-build (offline, strict, for untrusted builds) and confine (gui-safe)
export def link [cfg: record] {
    link-commands sandbox-build.nu confine.nu
}
