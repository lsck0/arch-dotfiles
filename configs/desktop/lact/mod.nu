use module.nu *

export const meta = {packages: {native: [amdgpu_top lact]}, volatile: true, native_only: [system]}

# the GPUs lactd tunes; on an Intel-only machine, a VM or a headless server it would idle as a root daemon
const VENDORS = [amd nvidia]

export def system [cfg: record] {
    if (gpu-list | where vendor in $VENDORS | is-empty) { return [] }
    unit-enable lactd.service --now
}
