use module.nu *

export const meta = {packages: {native: [scx-scheds]}}

export def system [cfg: record] {
    let supported = ("/sys/kernel/sched_ext" | path exists) and (which scx_lavd | is-not-empty)
    # laptop only: lavd ignores cgroup cpu.weight, which the desktop needs for session.slice (base/oomd)
    if $env.FORM_FACTOR? != "laptop" or not $supported { return [] }
    unit-file scx-lavd.service --enable --now --then [sh -c "systemctl restart scx-lavd.service || true"]
}
