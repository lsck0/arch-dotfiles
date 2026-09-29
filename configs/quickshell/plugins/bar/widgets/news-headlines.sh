#!/usr/bin/env bash
# nyt public rss, no api key needed
set -euo pipefail

curl -s --max-time 8 "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml" | python3 -c '
import sys, json, xml.etree.ElementTree as ET

data = sys.stdin.read()
try:
    root = ET.fromstring(data)
    titles = [item.findtext("title", "").strip() for item in root.iter("item")]
    titles = [t for t in titles if t][:5]
except ET.ParseError:
    titles = []

print(json.dumps(titles))
'
