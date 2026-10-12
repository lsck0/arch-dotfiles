#!/usr/bin/env bash
# Chromium ships with Google metrics, Safe-Browsing phone-home and Google search on by default. Managed policy
# in /etc survives updates and applies to every user and every --user-data-dir (the capgemini work profile too).
# Safe Browsing stays on standard protection (level 1): a local hash list, but a prefix match still sends that URL's
# hashed prefixes to Google to confirm, so it is not local-only; owner keeps the level. no sync, no sign-in, no
# password manager (proton pass is the one);
# uBlock Origin Lite is forced. doh is off like firefox: resolved's dot is the resolver and doh would bypass portmaster.
# Third-party cookies are blocked except for the microsoft 365 and capgemini ping sign-in, whose silent token renewal
# runs in iframes; camera and mic are asked per origin.
# Search = the homelab SearXNG like firefox; off the homelab, where that host isn't reachable, fall back to
# DuckDuckGo rather than Google.

DEST=/etc/chromium/policies/managed/policy.json

if [[ -n "$HOMELAB" ]]; then
    install -Dm644 policy.json "$DEST"
else
    jq '.DefaultSearchProviderName="DuckDuckGo"
        | .DefaultSearchProviderSearchURL="https://duckduckgo.com/?q={searchTerms}"' policy.json \
        | install -Dm644 /dev/stdin "$DEST"
fi

# new profiles (the capgemini one included) start on the gtk theme, which oomox renders from the wal palette; chromium
# picks it by itself only on gnome-likes, under hyprland it stays classic. BrowserThemeColor would pin one colour for
# every user instead. initial_preferences is read next to the real binary, a file the package does not own
if [[ -d /usr/lib/chromium ]]; then
    install -Dm644 initial_preferences /usr/lib/chromium/initial_preferences
fi
