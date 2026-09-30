# vm-test/vm-test.py guest, everything the desktop gets
HOSTNAME=vm-test
PKG_GROUPS=(base fonts desktop socials gaming creating latex programming qemu llm pentesting)
BOOT_FEATURES=(timeshift sbctl luks grub)
# packages this machine builds itself instead of taking them from the lsck0 mirror
MIRROR_SKIP=()
