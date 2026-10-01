# shellcheck shell=bash
# guest gating: config skips luca-only secrets, identity and services when the login user is not luca

# is_personal: true only on luca's own login, the gate for every personal config step
is_personal() { [[ "$(id -un)" == luca ]]; }
