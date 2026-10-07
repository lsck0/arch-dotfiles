# shellcheck shell=bash
# the root-owned copy the system layer runs from: root never executes a file a user can write, so the admin's checkout
# is packed by the user and unpacked by a fixed root command (no repo code) into SYSTEM_REPO

SYSTEM_REPO=/var/lib/dotfiles/repo
# ledger, patches-applied, boot stamps, FAILURES and the lock: machine state, outside the copy that every refresh replaces
SYSTEM_STATE=/var/lib/dotfiles
# what the system layer may read; skills, weblinks, wallpapers and secrets stay out
SYSTEM_PATHS=(configs patches platforms profiles scripts stage.sh)
# secret data the system modules consume, streamed by the admin's run on the root step's stdin, never sourced; plus $WIREGUARD
SYSTEM_SECRETS=(samba-homelab home-gateways wifi)
DOTFILES_URL=https://github.com/lsck0/arch-dotfiles.git

# root side of system_copy: $1 copy, $2 source sha; the tar on stdin. extracted beside the copy, swapped in only when
# complete, under the same lock system-apply holds, so a run never sees a half-written copy
SYSTEM_COPY_UNPACK='set -e
umask 022
copy=$1
mkdir -p "${copy%/*}"
exec 9>"${copy%/*}/lock"
flock 9
rm -rf "$copy.new"
mkdir "$copy.new"
tar -x --no-same-owner --no-same-permissions -C "$copy.new" -f -
printf "%s\n" "$2" >"$copy.new/.source"
rm -rf "$copy"
mv "$copy.new" "$copy"'

# system_copy <checkout> <copy> [runner...]: refresh <copy> from <checkout>'s tracked and untracked (not ignored) files,
# forward only: refused, old copy kept, unless the copy's .source is an ancestor of the checkout's HEAD
system_copy() {
    local checkout="$1" copy="$2" head old file
    local -a files=()
    shift 2
    head=$(git -C "$checkout" rev-parse HEAD) || return 1
    if [[ -f "$copy/.source" ]]; then
        old=$(<"$copy/.source")
        if ! git -C "$checkout" merge-base --is-ancestor "$old" "$head" 2>/dev/null; then
            echo "system: $copy is at $old, not an ancestor of $checkout's HEAD $head; keeping it, pull first" >&2
            return 1
        fi
    fi
    # a guest machine's platform file from before the system layer, moved to the machine once, before the pack so the copy never holds it
    if [[ -f "$checkout/platforms/local.sh" && -n "${PLATFORM_LOCAL:-}" && ! -e "$PLATFORM_LOCAL" ]]; then
        "$@" install -Dm644 "$checkout/platforms/local.sh" "$PLATFORM_LOCAL" && rm -f "$checkout/platforms/local.sh"
    fi
    # symlinks stay out (one could point into /home), a deleted tracked file has nothing to pack, a submodule becomes an empty dir
    while IFS= read -r -d '' file; do
        [[ -L "$checkout/$file" || ! -e "$checkout/$file" ]] || files+=("$file")
    done < <(git -C "$checkout" ls-files -z --cached --others --exclude-standard --deduplicate -- "${SYSTEM_PATHS[@]}")
    # a failed listing must never become an empty copy: the entry point itself has to be in it
    [[ " ${files[*]} " == *" scripts/lib/system-apply.sh "* ]] \
        || { echo "system: $checkout lists no scripts/lib/system-apply.sh, not copying" >&2; return 1; }
    # a truncated archive fails the root side's tar before the swap
    (
        set -o pipefail
        # modes as a fresh clone has them (644, 755 when executable by the owner), whatever the admin's umask
        printf '%s\0' "${files[@]}" | tar -C "$checkout" --no-recursion --null -T - --mode='go=u,go-w' -cf - \
            | "$@" sh -c "$SYSTEM_COPY_UNPACK" sh "$copy" "$head"
    ) || return 1
}
