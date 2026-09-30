# desktop; bootstrap.sh, install.sh and config.sh read this when the hostname matches
HOSTNAME=luca-pc
PKG_GROUPS=(base fonts desktop socials gaming creating latex programming qemu llm pentesting)
BOOT_FEATURES=(timeshift sbctl luks grub)
# secrets tunnel config for wg0
WIREGUARD=wg0.pc.conf
# packages this machine builds itself instead of taking them from the lsck0 mirror
MIRROR_SKIP=()
