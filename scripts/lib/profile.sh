# shellcheck shell=bash
# the running user's facts, sourced only by the user layer (and yubikey.sh): no file, or empty fields, is a guest.
# created from profiles/<user>.sh by bootstrap.sh, adduser-dotfiles or patch 22; PROFILE_FILE overrides it (bootstrap's template)

PROFILE_FILE="${PROFILE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile.sh}"

# profile_load: reset every field, then source the profile if there is one
profile_load() {
    PROFILE_CAPABILITIES=()
    PROFILE_NAME=""
    PROFILE_EMAIL=""
    PROFILE_GPG_FINGERPRINT=""
    [[ -f "$PROFILE_FILE" ]] || return 0
    # shellcheck source=/dev/null
    source "$PROFILE_FILE"
}

# profile_has <capability>: secrets (unlock with the yubikey), identity (name, keys, accounts) or homelab (nas, ntfy, sync)
profile_has() {
    [[ " ${PROFILE_CAPABILITIES[*]-} " == *" $1 "* ]]
}
