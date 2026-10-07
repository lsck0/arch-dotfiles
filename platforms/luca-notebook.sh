# laptop; bootstrap.sh offers it, install.sh, config.sh and the root copy read it when the hostname matches
HOSTNAME=luca-notebook
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=laptop
# board-specific: the synaptics 06cb:009a fingerprint reader
EXTRA_PACKAGES=(python-validity-git)
PKG_GROUPS=(base hardware fonts desktop socials creating latex programming pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.laptop.conf
# the homelab: pacman mirror line, nas mount, home gateways and routes, searxng in the firefox policy
HOMELAB=1
# sbctl enrolls this machine's own secure boot keys
SECURE_BOOT_OWN_KEYS=1
