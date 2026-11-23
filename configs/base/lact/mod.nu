use module.nu *

export const meta = {packages: {native: [amdgpu_top lact]}, native_only: [system]}

export def system [cfg: record] {
    unit-enable lactd.service --now
}
