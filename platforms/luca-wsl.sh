# windows host; bootstrap.sh, install.sh and config.sh read this when the hostname matches
HOSTNAME=luca-wsl
# desktop, laptop, vm or wsl: windows owns kernel, boot, drivers, power, audio and network, so no [hardware]
FORM_FACTOR=wsl
# gui programming tools draw through wslg
PKG_GROUPS=(base programming)
