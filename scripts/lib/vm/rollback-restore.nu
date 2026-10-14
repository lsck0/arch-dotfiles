use prelude.nu *

let kver = ^uname -r | str trim
say kver_bumped $kver
say esp_kver (output { ^file -bL "/boot/vmlinuz-@PKGBASE@" } | parse --regex 'version (?<v>\S+)' | get v | str join "\n")
report
if $kver != "@KVER_NEW@" { exit 0 }
# timeshift reboots on its own once @ is swapped; the reboot below covers a run that returns instead
say restore_rc (try { ^timeshift --restore --snapshot "@SNAPSHOT@" --scripted --yes --skip-grub; "0" } catch {|e| $e.exit_code? | into string })
report
^systemctl reboot
