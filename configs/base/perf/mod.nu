use module.nu *

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    # tolerant, unlike udev-reload: a failed trigger never fails the apply
    udev-rules 60-ioschedulers.rules --then [sh -c "udevadm control --reload; udevadm trigger --subsystem-match=block; true"]
}
