use prelude.nu *

const ARCHIVE_URL = "https://archive.archlinux.org/packages"

def vercmp [a: string, b: string]: nothing -> int { ^vercmp $a $b | str trim | into int }

let kver = ^uname -r | str trim
let pkgbase = open --raw $"/usr/lib/modules/($kver)/pkgbase" | str trim
let new = package-version $pkgbase
say pkgbase $pkgbase
say kver_new $kver
say kernel_new $new
let url = $"($ARCHIVE_URL)/($pkgbase | str substring 0..0)/($pkgbase)"
let old = output { ^curl -fsL $"($url)/" }
    | parse --regex ($'"($pkgbase)-' + '(?<v>[^"]+)-x86_64\.pkg\.tar\.zst"')
    | get v
    | reduce --fold null {|v, best| if (vercmp $v $new) < 0 and ($best == null or (vercmp $v $best) > 0) { $v } else { $best } }
say kernel_old ($old | default none)
if $old != null { do --ignore-errors { ^pacman -U --noconfirm $"($url)/($pkgbase)-($old)-x86_64.pkg.tar.zst" } }
let now = package-version $pkgbase
let downgraded = $old != null and $now == $old
say downgraded ($downgraded | yesno)
report
if $downgraded { ^systemctl reboot }
