# laptop; bootstrap.sh offers it, install.sh, config.sh and the root copy read it when the hostname matches
HOSTNAME=luca-notebook
# desktop, laptop, vm or wsl: the one answer every link.sh, tlp, hyprland and the power toggle read
FORM_FACTOR=laptop
# board-specific: the synaptics 06cb:009a fingerprint reader; vulkan-intel is the ICD for the UHD 620, without it
# mpv's vo=gpu-next (libplacebo/vulkan) finds no device and crashes instead of falling back
EXTRA_PACKAGES=(python-validity-git vulkan-intel)
# the intel uhd 620 render node for obs vaapi encoders (configs/creating/obs)
VAAPI_RENDER_NODE=/dev/dri/by-path/pci-0000:00:02.0-render
PKG_GROUPS=(base core fonts desktop socials creating latex programming pentesting)
# secrets tunnel config for wg0
WIREGUARD=wg0.laptop.conf
# the homelab: pacman mirror line, nas mount, home gateways and routes, searxng in the firefox policy
HOMELAB=1
# sbctl enrolls own secure boot keys and the event log's option rom hashes, no microsoft ca
SECURE_BOOT_OWN_KEYS=1
