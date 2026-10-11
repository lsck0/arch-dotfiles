#!/usr/bin/env bash
# profiles.conf keeps every program that opens other people's content in enforce and the module's own profiles are
# well formed; where apparmor.d is installed, every name exists and every profile and drop-in compiles. no root,
# run by ./test.py lint. the loaded modes themselves are checked by system.sh at the end of every config run.
# APPARMOR_D_SRC and APPARMOR_ETC point the compile step at an apparmor.d build instead of the installed one
set -euo pipefail

cd "$(dirname "$0")"
SRC=${APPARMOR_D_SRC:-/usr/share/apparmor.d}
ETC=${APPARMOR_ETC:-/etc/apparmor.d}
status=0
fail() { echo "apparmor.test: $*" >&2; status=1; }

# browsers, mail, chat, media, documents, images, torrents, archives, and the openers they all hand links to
ENFORCED=(firefox chromium qutebrowser lynx thunderbird discord signal-desktop telegram-desktop hexchat zapzap spotify
    mpv zathura sioyek okular bookokrat libreoffice onlyoffice feh nsxiv imv qbittorrent ouch 7z unrar unzip magick
    pdftoppm ffmpegthumbnailer child-open child-open-any child-open-browsers child-open-strict)

rows=$(awk '/^[^#]/ && NF' profiles.conf)
while read -r name mode extra; do
    [[ -z "$extra" && ("$mode" == enforce || "$mode" == complain) ]] || fail "profiles.conf: bad row '$name $mode $extra'"
done <<<"$rows"
dups=$(awk '{print $1}' <<<"$rows" | sort | uniq -d)
[[ -z "$dups" ]] || fail "profiles.conf lists twice: $dups"
for name in "${ENFORCED[@]}"; do
    [[ "$(awk -v p="$name" '$1 == p {print $2}' <<<"$rows")" == enforce ]] || fail "$name is not enforced in profiles.conf"
done

# the module's own: listed, marked for aa.sh, named after the file, with the flags clause system.sh puts the mode in
for src in profiles/*; do
    name=${src##*/}
    grep -q "^$name " <<<"$rows" || fail "profiles/$name is not in profiles.conf"
    [[ "$(head -n1 "$src")" == '# managed by arch-dotfiles/apparmor' ]] || fail "profiles/$name lacks the marker line"
    grep -q "^profile $name @{exec_path} flags=(" "$src" || fail "profiles/$name has no 'profile $name ... flags=(' line"
done
for src in local/*; do
    grep -q "^${src##*/} " <<<"$rows" || fail "local/${src##*/} extends no profile of profiles.conf"
done

if [[ -d "$SRC" && -e "$ETC/abstractions/base-strict" ]] && command -v apparmor_parser >/dev/null; then
    upstream=$(find "$SRC" -type f -not -path '*/abstractions/*' -not -path '*/tunables/*' -printf '%f\n')
    while read -r name _; do
        if [[ -e "profiles/$name" ]]; then
            ! grep -qxF "$name" <<<"$upstream" || fail "apparmor.d now ships $name, drop profiles/$name"
        else
            grep -qxF "$name" <<<"$upstream" || fail "apparmor.d has no profile named $name"
        fi
    done <<<"$rows"

    # the repo's abstractions and drop-ins in front of the installed ones
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/abstractions/dotfiles" "$work/local"
    cp abstractions/* "$work/abstractions/dotfiles/"
    cp local/* "$work/local/"
    parse() {
        apparmor_parser --skip-kernel-load --skip-cache --base "$ETC" -I "$work" -I "$ETC" \
            --features-file "$ETC/abi/4.0" "$1" >/dev/null
    }
    for src in profiles/*; do
        parse "$src" || fail "profiles/${src##*/} does not compile"
    done
    # an upstream profile apparmor.d deployed here, under its overwrite name when it replaced a stock one
    for src in local/*; do
        for target in "$ETC/${src##*/}.apparmor.d" "$ETC/${src##*/}"; do
            [[ -f "$target" ]] || continue
            parse "$target" || fail "$target does not compile with local/${src##*/}"
            break
        done
    done
fi
exit "$status"
