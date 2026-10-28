use module.nu *

export const meta = {packages: {pacman: [pass pass-otp]}, inputs: [~/sync/password-store/.gpg-id]}

export def link [cfg: record] {
    if not (owner-unlocked) { return [] }
    let store = $nu.home-dir | path join .password-store
    let synced = $nu.home-dir | path join sync password-store
    let fpr = (profile-load).gpg_fingerprint
    # the store and its .gpg-id are syncthing's: dot never runs `pass init` there, a half-synced folder would fork it
    if not ($synced | path join .gpg-id | path exists) {
        log-info $"pass: ($synced) has no .gpg-id yet; it arrives with syncthing, or start a store with: pass init ($fpr)"
    }
    [(file-link $synced $store)]
}
