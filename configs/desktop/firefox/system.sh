#!/usr/bin/env bash

FIREFOX_DIR=/usr/lib/firefox
POLICIES=/etc/firefox/policies/policies.json

# new tab url is only settable from autoconfig in the install dir; files there survive firefox updates.
# mozilla.cfg reads each user's own home dir at runtime, so one copy serves every user
if [[ -d "$FIREFOX_DIR" ]]; then
    install -Dm644 autoconfig.js "$FIREFOX_DIR/defaults/pref/autoconfig.js"
    install -Dm644 mozilla.cfg "$FIREFOX_DIR/mozilla.cfg"
fi

# hardening and the default search engine: the enterprise policy is the only reliable path, /etc survives updates and
# reaches every profile of every user. strict etp minus total cookie protection: cookie behavior 5 partitions storage
# and broke teams screen share, so normal windows reject tracker cookies only (4), private ones partition too.
# doh is off and locked: resolved's dot is the resolver, and doh would bypass portmaster's filter lists and the
# homelab's internal names. uBlock Origin is forced for everyone; privacy badger is installed but can be switched off,
# with the microsoft/ping sign-in and capgemini sites exempt; noscript has no managed settings, so it stays a per-user
# choice. the engine is the homelab's searxng, so only a homelab machine gets it, elsewhere only an exact copy of ours
# goes, never a foreign file
if [[ -n "$HOMELAB" ]]; then
    install -Dm644 policies.json "$POLICIES"
else
    # off the homelab the searxng host isn't reachable; set DuckDuckGo as default rather than leaving firefox on Google
    jq '.policies.SearchEngines = {
            "Add": [{"Name": "DuckDuckGo", "URLTemplate": "https://duckduckgo.com/?q={searchTerms}", "Method": "GET", "Alias": "ddg"}],
            "Default": "DuckDuckGo"
        }' policies.json | install -Dm644 /dev/stdin "$POLICIES"
fi
