# desktop; bootstrap.sh offers it, install.sh, config.sh and the root copy read it when the hostname matches
HOSTNAME=luca-pc
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=desktop
# board-specific: it87 for the gigabyte x870e fan headers, amdgpu_top and the rocm group for the rx 7800 xt
EXTRA_PACKAGES=(it87-dkms-git amdgpu_top)
PKG_GROUPS=(base hardware fonts desktop socials gaming creating latex programming qemu llm rocm pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.pc.conf
# the homelab: pacman mirror line, nas mount, home gateways and routes, searxng in the firefox policy
HOMELAB=1
# sbctl enrolls this machine's own secure boot keys
SECURE_BOOT_OWN_KEYS=1
