#!/usr/bin/env bash
# Daily borg backup of $HOME into a local repo inside the syncthing folder borg-<host> (configs/core/syncthing), which
# ships it to the NAS; the laptop backs up while away and syncs later. repokey-blake2 with the passphrase from
# secrets/borg-passphrase, so the NAS and anything behind it only ever hold ciphertext. A missing passphrase or locked
# secrets fail the run (failure-notify reports it); battery and metered links skip it quietly until the last good
# run is older than STALE_DAYS. Weekly `borg check --repository-only`, monthly a restore of a canary file.
set -euo pipefail
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
export DOTFILES
source "$DOTFILES/scripts/lib/secrets.sh"

HOST=$(hostname)
# the syncthing folder (configs/core/syncthing/link.sh has the same path and id)
FOLDER="${XDG_DATA_HOME:-$HOME/.local/share}/borg-repo"
FOLDER_ID="borg-$HOST"
SECRETS="${DOTFILES_SECRETS:-$DOTFILES/secrets}"
PASSFILE="$SECRETS/borg-passphrase"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/borg"
CANARY="$STATE/canary"
STALE_DAYS=3
CHECK_DAYS=7
RESTORE_DAYS=30

# stamp_older <name> <days>: true when the stamp is missing or older than <days>
stamp_older() {
    [[ -z "$(find "$STATE/$1" -mmin -$(($2 * 24 * 60)) 2>/dev/null)" ]]
}

# skip <why>: quiet while a recent backup exists, a failure once the last good one is too old
skip() {
    echo "borg: $1, skipping" >&2
    if stamp_older last-success "$STALE_DAYS"; then
        echo "borg: no backup in the last $STALE_DAYS days (last: $(date -r "$STATE/last-success" 2>/dev/null || echo never))" >&2
        exit 1
    fi
    exit 0
}

# the same test as ConditionACPower=, here so a skipped run still reports a stale backup
systemd-ac-power || skip "on battery"
# NetworkManager's global Metered: 1 yes, 3 guess-yes
metered=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager \
    org.freedesktop.NetworkManager Metered 2>/dev/null | cut -d' ' -f2) || metered=""
[[ "$metered" != 1 && "$metered" != 3 ]] || skip "metered connection"

[[ -s "$PASSFILE" ]] || { echo "borg: no passphrase, create secrets/borg-passphrase (configs/core/borg/README.md)" >&2; exit 1; }
# a locked blob would become the passphrase of a fresh repo
secret_is_plaintext "$PASSFILE" || { echo "borg: secrets are locked, unlock them (scripts/lib/yubikey.sh unlock)" >&2; exit 1; }

export BORG_PASSCOMMAND="cat ${PASSFILE@Q}"
export BORG_RELOCATED_REPO_ACCESS_IS_OK=no BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=no BORG_EXIT_CODES=legacy
# a lock left by a suspended run waits instead of failing
borg() { command borg --lock-wait 600 "$@"; }

mkdir -p "$STATE" "$FOLDER"
# a fresh random file that never changes: the monthly restore check extracts it and compares
[[ -s "$CANARY" ]] || head -c 4096 /dev/urandom >"$CANARY"

# syncthing must not ship a half-written transaction: the folder pauses for the run, unpausing rescans it
paused=false
resume() { ! $paused || syncthing cli config folders "$FOLDER_ID" paused set false || echo "borg: could not resume syncthing folder $FOLDER_ID" >&2; }
trap resume EXIT
if systemctl --user -q is-active syncthing.service; then
    folders=$(syncthing cli config folders list) || { echo "borg: syncthing runs but its api does not answer, not writing under it" >&2; exit 1; }
    if grep -qx "$FOLDER_ID" <<<"$folders"; then
        syncthing cli config folders "$FOLDER_ID" paused set true
        paused=true
    else
        echo "borg: no syncthing folder $FOLDER_ID, this backup stays on this machine" >&2
    fi
fi

# one repo per init, named by its creation: a reinstalled host starts a new one beside the copy the NAS still has,
# instead of syncing a fresh repo over the old one's files
shopt -s nullglob
repos=("$FOLDER/$HOST"-*/config)
shopt -u nullglob
if ((${#repos[@]} > 1)); then
    echo "borg: several repos in $FOLDER (${repos[*]%/config}), keep one" >&2
    exit 1
elif ((${#repos[@]} == 1)); then
    export BORG_REPO="${repos[0]%/config}"
else
    export BORG_REPO="$FOLDER/$HOST-$(date +%Y%m%d%H%M%S)"
    borg init --encryption=repokey-blake2
fi
# the key lives in the repo's config, a damaged config loses every archive: a copy (still passphrase-encrypted) in secrets
KEY_EXPORT="$SECRETS/borg-key-${BORG_REPO##*/}"
[[ -s "$KEY_EXPORT" ]] || (umask 077 && borg key export "$BORG_REPO" "$KEY_EXPORT")

# app state the restore needs in the repo checkout (secrets, plasma); sync.sh commits it. a failed one only warns
for script in "$DOTFILES"/scripts/lib/backup-*.sh; do
    "$script" >&2 || echo "borg: ${script##*/} failed, its app state is from an older run" >&2
done

# reproducible or already elsewhere: caches, toolchains, game and vm data, models, ~/sync (on the NAS itself)
excludes=(
    "$FOLDER" "$HOME/sync" "$HOME/downloads" "$HOME/Downloads"
    "$HOME/.cache" "$HOME/.local/share/Trash" "$HOME/.local/share/baloo" "$HOME/.var/app/*/cache"
    "$HOME/.steam" "$HOME/.local/share/Steam" "$HOME/.local/share/flatpak" "$HOME/.local/share/containers"
    "$HOME/.xlcore/ffxiv" "$HOME/.xlcore/wineprefix" "$HOME/.xlcore/compatibilitytool" "$HOME/.xlcore/runtime"
    "$HOME/.xlcore/dalamud" "$HOME/.xlcore/dalamudAssets" "$HOME/.xlcore/installedPlugins" "$HOME/.xlcore/logs"
    "$HOME/.local/share/libvirt/images" "$HOME/.local/share/gnome-boxes" "$HOME/.ollama/models" "$HOME/.lmstudio/models"
    "$HOME/.gradle" "$HOME/.m2/repository" "$HOME/.ghcup" "$HOME/.rustup" "$HOME/.cargo/registry" "$HOME/.cargo/git"
    "$HOME/.go/pkg" "$HOME/go/pkg" "$HOME/.npm" "$HOME/.opam" "$HOME/.local/share/mise" "$HOME/.local/share/zinit"
    "$HOME/.local/share/nvim/lazy" "$HOME/.local/share/nvim/mason" "$HOME/.local/share/torbrowser"
    "$HOME/**/node_modules" "$HOME/**/target" "$HOME/**/.venv"
)
rc=0
borg create --stats --compression auto,zstd,3 --exclude-caches --one-file-system --exclude-if-present .nobackup \
    "${excludes[@]/#/--exclude=}" "::{hostname}-{now:%Y%m%d-%H%M%S}" "$HOME" || rc=$?
# 1 is a warning (a file changed while read), routine for a live home; the archive exists
((rc <= 1)) || exit "$rc"

borg prune --glob-archives '{hostname}-*' --keep-daily 7 --keep-weekly 4 --keep-monthly 6
borg compact
touch "$STATE/last-success"

if stamp_older last-check "$CHECK_DAYS"; then
    borg check --repository-only
    touch "$STATE/last-check"
fi
if stamp_older last-restore "$RESTORE_DAYS"; then
    last=$(borg list --last 1 --short)
    borg extract --stdout "::$last" "${CANARY#/}" | cmp -s - "$CANARY" \
        || { echo "borg: restoring $CANARY from $last did not give the file back" >&2; exit 1; }
    touch "$STATE/last-restore"
fi
