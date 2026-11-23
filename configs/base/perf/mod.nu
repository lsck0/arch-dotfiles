use module.nu *

export const meta = {native_only: [system]}

export def system [cfg: record] {
    # tolerant, unlike udev-reload: a failed trigger never fails the apply
    udev-rules 60-ioschedulers.rules --then [sh -c "udevadm control --reload; udevadm trigger --subsystem-match=block; true"]
}
