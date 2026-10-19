const PROFILE_KEYS = [capabilities name email gpg_fingerprint]
export const PROFILE_CAPABILITIES = [secrets identity homelab work]

def profile-dir []: nothing -> path {
    $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join dotfiles
}

export def profile-options-file []: nothing -> path {
    profile-dir | path join options.nuon
}

def profile-guard []: nothing -> nothing {
    if (is-admin) {
        error make {msg: "the system layer never reads a user fact"}
    }
}

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

export def profile-has [capability: string]: nothing -> bool {
    if $capability not-in $PROFILE_CAPABILITIES {
        error make {msg: $"profile-has: unknown capability ($capability)"}
    }
    $capability in (profile-load).capabilities
}
