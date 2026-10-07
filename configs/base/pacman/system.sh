#!/usr/bin/env bash
# run by system-apply install before any sync: [lsck0] and its key, the pacman config and the root hooks

PACMAN_CONF=/etc/pacman.conf
HOOK_DIR=/etc/pacman.d/hooks

# trust the mirror.lsck0.dev signing key before pacman.conf names the repo
# a throwaway keyring: reading the key file must not leave a /root/.gnupg behind
gnupg_home=$(mktemp -d)
fingerprint=$(gpg --homedir "$gnupg_home" --show-keys --with-colons archrepo.asc | awk -F: '$1 == "fpr" {print $10; exit}')
rm -rf "$gnupg_home"
[[ -n "$fingerprint" ]] || { echo "pacman: no fingerprint in archrepo.asc" >&2; exit 1; }
pacman-key --add archrepo.asc
pacman-key --lsign-key "$fingerprint"
# LSCK0_SNAPSHOT=<YYYY-MM-DD> (platform file or env) pins [lsck0] to that night's dated snapshot instead of the latest
[[ "$LSCK0_SNAPSHOT" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})?$ ]] || { echo "pacman: LSCK0_SNAPSHOT '$LSCK0_SNAPSHOT' is not YYYY-MM-DD" >&2; exit 1; }
# [lsck0] always, so an unreachable snapshot fails the sync instead of mixing live core with snapshot sonames; rename, never a half-written file
sed "/^\[lsck0\]/,/^\[/ s|/\$arch\$|${LSCK0_SNAPSHOT:+/$LSCK0_SNAPSHOT}/\$arch|" pacman.conf | install -m644 /dev/stdin "$PACMAN_CONF.new"
mv -f "$PACMAN_CONF.new" "$PACMAN_CONF"

# hooks run as root: root-owned copies, never links into a checkout
for hook in hooks/*.hook; do
    install -Dm644 "$hook" "$HOOK_DIR/${hook#hooks/}"
done
