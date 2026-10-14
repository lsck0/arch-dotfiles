# shellcheck shell=bash
# runs on the test vm's guest as root, fetched by dot test (scripts/lib/vm.nu); @KEY@ placeholders are filled in there
kver=$(uname -r)
pkgbase=$(< "/usr/lib/modules/$kver/pkgbase")
new=$(pacman -Q "$pkgbase" | cut -d' ' -f2)
say pkgbase "$pkgbase"
say kver_new "$kver"
say kernel_new "$new"
url="https://archive.archlinux.org/packages/${pkgbase:0:1}/$pkgbase"
old=""
for v in $(curl -fsL "$url/" | grep -oE "\"$pkgbase-[^\"]+-x86_64\.pkg\.tar\.zst\"" |
    sed -E "s/^\"$pkgbase-//; s/-x86_64\.pkg\.tar\.zst\"\$//"); do
    if (($(vercmp "$v" "$new") < 0)) && { [[ -z "$old" ]] || (($(vercmp "$v" "$old") > 0)); }; then old=$v; fi
done
say kernel_old "${old:-none}"
[[ -z "$old" ]] || pacman -U --noconfirm "$url/$pkgbase-$old-x86_64.pkg.tar.zst"
now=$(pacman -Q "$pkgbase" | cut -d' ' -f2)
say downgraded "$(yesno test -n "$old" -a "$now" = "$old")"
report
[[ -z "$old" || "$now" != "$old" ]] || systemctl reboot
