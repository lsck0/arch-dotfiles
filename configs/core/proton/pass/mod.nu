use module.nu *

export const meta = {packages: {pacman: [pass pass-otp]}, inputs: [~/sync/password-store/.gpg-id]}

# the store lives in ~/sync, the only backed-up place outside git; anyone without an identity inits their own by hand
export def link [cfg: record] {
    if not (profile-has identity) { return [] }
    let store = $nu.home-dir | path join .password-store
    let synced = $nu.home-dir | path join sync password-store
    let fpr = (profile-load).gpg_fingerprint
    # made only by syncthing or a first `pass init`, never here before syncthing delivers the real one
    if not ($synced | path exists) {
        log-info $"pass: no ($synced) yet; it arrives with syncthing, or start one with: pass init ($fpr)"
    }
    let has_key = $fpr != "" and (^gpg --list-keys $fpr | complete).exit_code == 0
    let init = $has_key and ($synced | path exists) and not ($synced | path join .gpg-id | path exists)
    [
        (file-link $synced $store)
        (if $init { exec pass-init [pass init $fpr] } else { [] })
    ]
}
