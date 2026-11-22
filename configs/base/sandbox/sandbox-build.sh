#!/usr/bin/env bash
# Run a command offline in the work dir, e.g. `sandbox-build -- cargo test` or `sandbox-build -w ./crate -- make`.
set -euo pipefail

USAGE="usage: sandbox-build [-w|--work <dir>] [--] <command...>"
# home paths holding keys, tokens and browser or messenger sessions, relative to $HOME, one a line
SENSITIVE_HOME=$(dirname -- "$(readlink -f -- "$0")")/sensitive-home.txt
REPO=${DOTFILES:-$HOME/projects/arch-dotfiles}

usage_fail() {
    echo "$USAGE" >&2
    exit 2
}

work=$PWD
case ${1:-} in
    -h | --help)
        echo "$USAGE: run it offline, writable only in the work dir (default: here)"
        exit 0
        ;;
    -w | --work)
        [ $# -ge 2 ] || usage_fail
        work=$2
        shift 2
        ;;
    --work=*)
        work=${1#--work=}
        shift
        ;;
esac
[ "${1:-}" != -- ] || shift
[ $# -gt 0 ] || usage_fail
work=$(realpath --canonicalize-missing -- "$work")
# by path: systemd-run -p does not expand %t
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

properties=(
    PrivateNetwork=yes NoNewPrivileges=yes ProtectSystem=strict ProtectHome=read-only PrivateTmp=yes
    ProtectKernelTunables=yes ProtectKernelModules=yes ProtectControlGroups=yes RestrictSUIDSGID=yes LockPersonality=yes
    # hidden, not read-only: connect() still reaches the bus, the agents, wayland and systemd --user's socket
    InaccessiblePaths=-/run/dbus PrivateIPC=yes
    # BindPaths, not ReadWritePaths: a /tmp work dir is missing under PrivateTmp (226/NAMESPACE)
    "BindPaths=$work" "InaccessiblePaths=$runtime"
)
# ProtectHome=read-only still lets a build READ these and copy them into the work dir; hide them outright.
while IFS= read -r path; do
    properties+=("InaccessiblePaths=-$HOME/$path")
done < "$SENSITIVE_HOME"
# the git-crypt symmetric key decrypts every secret; the module copy lives under .git, the submodule's under .git/modules
properties+=(
    "InaccessiblePaths=-$REPO/configs/secrets"
    "InaccessiblePaths=-$REPO/.git/git-crypt"
    "InaccessiblePaths=-$REPO/.git/modules/configs/secrets/git-crypt"
)
if [ -e "$work/.git" ]; then
    properties+=("ReadOnlyPaths=$work/.git")
fi
exec systemd-run --user --pty --wait --collect --quiet "--unit=sandbox-build-$$" "--working-directory=$work" \
    "${properties[@]/#/--property=}" -- "$@"
