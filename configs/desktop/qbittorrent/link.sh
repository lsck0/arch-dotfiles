#!/usr/bin/env bash
# Bind qBittorrent to the ProtonVPN tunnel (proton0): torrent traffic only flows while the VPN is up, and when
# proton0 is down qBittorrent binds to a missing interface and stalls instead of leaking over the real one. This
# is the reliable per-app killswitch, independent of the system routing/firewall toggles. qBittorrent rewrites
# its own config on exit, so the binding keys are re-asserted here on every config run.

conf="${XDG_CONFIG_HOME:-$HOME/.config}/qBittorrent/qBittorrent.conf"
mkdir -p "$(dirname "$conf")"

VPN_INTERFACE=proton0 python3 - "$conf" <<'PY'
import configparser, os, sys

path = sys.argv[1]
iface = os.environ["VPN_INTERFACE"]

cp = configparser.RawConfigParser()      # Raw: qBittorrent values contain % and \, no interpolation
cp.optionxform = str                     # keys are case-sensitive
if os.path.exists(path):
    cp.read(path)

def setkey(section, key, val):
    if not cp.has_section(section):
        cp.add_section(section)
    cp.set(section, key, val)

def seed(section, key, val):             # only if absent, so a later manual change in qBittorrent sticks
    if not (cp.has_section(section) and cp.has_option(section, key)):
        setkey(section, key, val)

# always enforced: bind to the tunnel; empty address = any address on that interface
setkey("BitTorrent", r"Session\InterfaceName", iface)
setkey("BitTorrent", r"Session\InterfaceAddress", "")

# seeded once
seed("LegalNotice", "Accepted", "true")                      # skip the first-run EULA dialog
seed("BitTorrent", r"Session\Encryption", "0")               # prefer encrypted peer connections
seed("Preferences", r"Advanced\AnnounceToAllTrackers", "true")

with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)               # qBittorrent wants key=value
PY
