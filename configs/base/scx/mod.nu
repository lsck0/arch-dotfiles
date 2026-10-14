use module.nu *

export const meta = {packages: {native: [scx-scheds]}}

# laptop only: scx_lavd's core compaction and frequency control save power, but it ignores cgroup cpu.weight, so the
# desktop keeps eevdf, where session.slice (base/oomd) outweighs a build; nice applies under both
export def system [cfg: record] {
    let supported = ("/sys/kernel/sched_ext" | path exists) and (which scx_lavd | is-not-empty)
    if $env.FORM_FACTOR? != "laptop" or not $supported { return [] }
    # a failed attach falls back to eevdf, the next boot retries
    unit-file scx-lavd.service --enable --now --then [sh -c "systemctl restart scx-lavd.service || true"]
}
