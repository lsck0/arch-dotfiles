# The NAS's vendor dir: re-downloadable installers and engines, outside syncthing. Modules copy or unpack from it at
# apply time and keep working off their local copy while it is away.
use ../../../platforms/homelab.nu [HOMELAB]

export const NAS_MOUNT = "/mnt/homelab"
# mnt-homelab.mount's conditions: off both a stat through the automount fails at once, on them a dead route hangs
# until the mount's TimeoutSec
const HOME_NETWORK = "/run/home-network"
const WG_LINK = "/sys/class/net/wg0"

# null while the share is not reachable (away from home without wg0, no homelab platform, the NAS down).
export def nas-vendor-dir []: nothing -> any {
    if not (($HOME_NETWORK | path exists) or ($WG_LINK | path exists)) { return null }
    let dir = $NAS_MOUNT | path join $HOMELAB.nas.vendor
    if ($dir | path type) == dir { $dir }
}

# The newest file in vendor matching pattern by natural sort (versions in the name), null without one or a vendor dir.
export def nas-vendor-newest [vendor: any, pattern: string]: nothing -> any {
    if $vendor == null { return null }
    glob ($vendor | path join $pattern) | sort --natural | last
}

# Whether candidate (a file name or version from the NAS) sorts naturally after installed, "" when none is.
export def nas-vendor-newer [installed: string, candidate: string]: nothing -> bool {
    $candidate != "" and $candidate != $installed and ([$installed $candidate] | sort --natural | last) == $candidate
}
