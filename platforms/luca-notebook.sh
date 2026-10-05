# laptop; bootstrap.sh, install.sh and config.sh read this when the hostname matches
HOSTNAME=luca-notebook
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=laptop
# board-specific: the synaptics 06cb:009a fingerprint reader
EXTRA_PACKAGES=(python-validity-git)
PKG_GROUPS=(base hardware fonts desktop socials creating latex programming pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.laptop.conf
