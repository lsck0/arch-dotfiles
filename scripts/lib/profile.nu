# User capabilities and identity from ~/.config/dotfiles/profile.nuon; the system layer never reads them.

use state.nu [SYSTEM_STATE xdg]

const PROFILE_KEYS = [capabilities name email gpg_fingerprint]
export const PROFILE_CAPABILITIES = [secrets]
export const PROFILE_OWNERS_FILE = $SYSTEM_STATE | path join owners

def profile-dir []: nothing -> path {
    xdg config dotfiles
}

export def profile-options-file []: nothing -> path {
    profile-dir | path join options.nuon
}

def profile-guard []: nothing -> nothing {
    if (is-admin) {
        error make {msg: "the system layer never reads a user fact"}
    }
}

# The profile (PROFILE_FILE first) with its option values; unknown keys or capabilities and root are errors.
export def profile-load []: nothing -> record {
    profile-guard
    let file = [($env.PROFILE_FILE? | default "") (profile-dir | path join profile.nuon)]
        | where {|f| $f != "" and ($f | path exists) } | get --optional 0
    let raw = if $file == null { {} } else { open $file }
    let unknown = $raw | columns | where $it not-in $PROFILE_KEYS
    if ($unknown | is-not-empty) {
        error make {msg: $"($file): unknown keys ($unknown | str join ', ')"}
    }
    let caps = $raw.capabilities? | default []
    let bad = $caps | where $it not-in $PROFILE_CAPABILITIES
    if ($bad | is-not-empty) {
        error make {msg: $"($file): unknown capabilities ($bad | str join ', ')"}
    }
    let options_file = profile-options-file
    {
        file: $file
        capabilities: $caps
        name: ($raw.name? | default "")
        email: ($raw.email? | default "")
        gpg_fingerprint: ($raw.gpg_fingerprint? | default "")
        options_file: $options_file
        options: (if ($options_file | path exists) { open $options_file } else { {} })
    }
}

# Whether the profile grants capability; an unknown capability is an error.
export def profile-has [capability: string]: nothing -> bool {
    if $capability not-in $PROFILE_CAPABILITIES {
        error make {msg: $"profile-has: unknown capability ($capability)"}
    }
    $capability in (profile-load).capabilities
}

# Whether an owner (a login with the secrets capability) uses this machine: the system layer reads no profile, so it
# asks the owners record bootstrap and system-apply keep, also when a user plans it.
export def profile-owner []: nothing -> bool {
    if not (is-admin) and $env.DOT_LAYER? != "system" { return (profile-has secrets) }
    (try { open --raw $PROFILE_OWNERS_FILE } catch { "" } | str trim) != ""
}

# Records login as an owner in the owners file under root ("" for this system, the target's mount while installing).
export def profile-owner-add [login: string, root: string = ""]: nothing -> nothing {
    let owners = $"($root)($PROFILE_OWNERS_FILE)"
    mkdir ($owners | path dirname)
    let have = if ($owners | path exists) { open --raw $owners | lines } else { [] }
    if $login not-in $have { $"($login)\n" | save --append $owners }
}
