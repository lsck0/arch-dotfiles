#!/usr/bin/env bash
# Chromium ships with Google metrics, Safe-Browsing phone-home and Google search on by default. Managed policy
# in /etc survives updates and applies to every user. Search = the homelab SearXNG like firefox; off the homelab,
# where that host isn't reachable, fall back to DuckDuckGo rather than Google.

DEST=/etc/chromium/policies/managed/policy.json

if [[ -n "$HOMELAB" ]]; then
    install -Dm644 policy.json "$DEST"
else
    jq '.DefaultSearchProviderName="DuckDuckGo"
        | .DefaultSearchProviderSearchURL="https://duckduckgo.com/?q={searchTerms}"' policy.json \
        | install -Dm644 /dev/stdin "$DEST"
fi
