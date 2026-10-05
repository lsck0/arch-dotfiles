# desktop; bootstrap.sh, install.sh and config.sh read this when the hostname matches
HOSTNAME=luca-pc
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=desktop
# board-specific: it87 for the gigabyte x870e fan headers, amdgpu_top and the rocm group for the rx 7800 xt
EXTRA_PACKAGES=(it87-dkms-git amdgpu_top)
PKG_GROUPS=(base hardware fonts desktop socials gaming creating latex programming qemu llm rocm pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.pc.conf
