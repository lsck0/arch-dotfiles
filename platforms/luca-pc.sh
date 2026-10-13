# desktop; bootstrap.sh offers it, install.sh, config.sh and the root copy read it when the hostname matches
HOSTNAME=luca-pc
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=desktop
# board-specific: it87 for the gigabyte x870e fan headers, amdgpu_top and the rocm group for the rx 7800 xt; vulkan-radeon
# is the ICD for gpu-next/libplacebo (so far only pulled transitively by steam), pinned here so it never depends on that.
# the last four are for REMOTE_UNLOCK (initramfs ssh, configs/base/boot/remote-unlock)
EXTRA_PACKAGES=(it87-dkms-git amdgpu_top vulkan-radeon mkinitcpio-systemd-tool tinyssh tinyssh-convert busybox)
# wake-on-lan this box, then ssh into the initramfs to unlock LUKS remotely (configs/base/boot/remote-unlock)
REMOTE_UNLOCK=1
PKG_GROUPS=(base core fonts desktop socials gaming creating latex programming qemu llm rocm pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.pc.conf
# the homelab: pacman mirror line, nas mount, home gateways and routes, searxng in the firefox policy
HOMELAB=1
# sbctl enrolls own secure boot keys and the event log's option rom hashes, no microsoft ca
SECURE_BOOT_OWN_KEYS=1
