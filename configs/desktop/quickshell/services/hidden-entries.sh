#!/usr/bin/env bash
# launcher ids to hide beyond NoDisplay: Hidden=true, or OnlyShowIn/NotShowIn against the desktops in $1 (a:b)
IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
dirs=("$HOME/.local/share/applications")
for dir in "${data_dirs[@]}"; do dirs+=("${dir%/}/applications"); done
dirs+=("$HOME/.nix-profile/share/applications")

for dir in "${dirs[@]}"; do
  [[ -d $dir ]] && find "$dir" -type f -name '*.desktop' 2>/dev/null | sort | sed "s|^|$dir\t|"
done | awk -F'\t' -v desktops=":${1:-}:" '
  function listed(list,   parts, n, i) {
    n = split(list, parts, ";")
    for (i = 1; i <= n; i++) if (parts[i] != "" && index(desktops, ":" parts[i] ":")) return 1
    return 0
  }
  {
    id = substr($2, length($1) + 2)
    sub(/\.desktop$/, "", id)
    gsub("/", "-", id)
    if (id in seen) next
    seen[id] = 1
    section = ""; hidden = 0; only = ""; not = ""
    while ((getline line < $2) > 0) {
      sub(/\r$/, "", line)
      if (line ~ /^\[.*\]$/) { section = line; continue }
      if (section != "[Desktop Entry]") continue
      key = line
      sub(/=.*/, "", key)
      value = substr(line, length(key) + 2)
      if (key == "Hidden" && value == "true") hidden = 1
      else if (key == "OnlyShowIn") only = value
      else if (key == "NotShowIn") not = value
    }
    close($2)
    if (hidden || (only != "" && !listed(only)) || (not != "" && listed(not))) print id
  }'
