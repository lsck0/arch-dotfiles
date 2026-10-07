# windows host; bootstrap.sh offers it, install.sh, config.sh and the root copy read it when the hostname matches
HOSTNAME=luca-wsl
# desktop, laptop, vm or wsl: windows owns kernel, boot, drivers, power, audio and network, so no [hardware]
FORM_FACTOR=wsl
# gui programming tools draw through wslg
PKG_GROUPS=(base programming)
# the homelab: pacman mirror line, nas mount, home gateways and routes, searxng in the firefox policy
HOMELAB=1
