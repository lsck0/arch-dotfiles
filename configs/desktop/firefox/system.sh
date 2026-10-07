#!/usr/bin/env bash

FIREFOX_DIR=/usr/lib/firefox
POLICIES=/etc/firefox/policies/policies.json

# new tab url is only settable from autoconfig in the install dir; files there survive firefox updates.
# mozilla.cfg reads each user's own home dir at runtime, so one copy serves every user
if [[ -d "$FIREFOX_DIR" ]]; then
    install -Dm644 autoconfig.js "$FIREFOX_DIR/defaults/pref/autoconfig.js"
    install -Dm644 mozilla.cfg "$FIREFOX_DIR/mozilla.cfg"
fi

# default search engine: the enterprise policy is the only reliable path, /etc survives updates; the engine is the
# homelab's searxng, so only a homelab machine gets it, elsewhere only an exact copy of ours goes, never a foreign file
if [[ -n "$HOMELAB" ]]; then
    install -Dm644 policies.json "$POLICIES"
elif cmp -s policies.json "$POLICIES"; then
    rm -f "$POLICIES"
fi
