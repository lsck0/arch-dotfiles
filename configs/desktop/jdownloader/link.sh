#!/usr/bin/env bash

# swing; the container-file entry (.dlc, .ccf, .rsdf) starts the same jvm
desktop_java_scale jdownloader.desktop
desktop_java_scale jd-containers.desktop

# JD2 runs in user scope (~/.jd, per /opt/JDownloaderScripts/functions.sh, unless the user is in the jdownloader
# group) and defaults to auto-checking and installing updates on start, uploading anonymous stats, and showing an
# in-gui ad banner. each cfg/<interface-fqn>.json is a flat object JD merges over its built-in defaults; the key is
# the getter name lowercased. JD rewrites these files itself, so the keys are merged in (never symlinked) and other
# keys are left alone. "offerware" proper is injected into the windows installer only, not into any cfg key
JD_CFG="${HOME}/.jd/cfg"
mkdir -p "$JD_CFG"
JD_CFG="$JD_CFG" python3 - <<'PY'
import json, os

cfg = os.environ["JD_CFG"]

# file -> {key: value}; every default is the opposite (update, stats and banner all on)
wanted = {
    "org.jdownloader.updatev2.UpdateSettings.json": {
        "autoupdatecheckenabled": False,        # no auto update check on start
        "installupdatesonexitenabled": False,   # and never install one on exit
    },
    "org.jdownloader.jdserv.stats.StatsManagerConfigV2.json": {
        "enabled": False,                        # no anonymous usage statistics
    },
    "org.jdownloader.settings.GraphicalUserInterfaceSettings.json": {
        "bannerenabled": False,                 # no premium-hoster ad banner
        "specialdealsenabled": False,           # no "special deals" offer dialogs
    },
}

for name, keys in wanted.items():
    path = os.path.join(cfg, name)
    data = {}
    if os.path.exists(path):
        try:
            with open(path) as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
        except (ValueError, OSError):
            data = {}
    data.update(keys)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
PY
