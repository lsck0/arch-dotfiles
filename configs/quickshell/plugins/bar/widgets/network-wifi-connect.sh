#!/usr/bin/env bash
# usage: <ssid> [password]; password falls back to configs/secrets/wifi
set -euo pipefail

ssid="${1:?ssid required}"
password="${2:-}"

secrets_wifi="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/configs/secrets/wifi"

# a saved NM profile wins over the secrets map, which may be stale
has_profile() {
  local name
  while IFS= read -r name; do
    [[ "$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null)" == "$ssid" ]] && return 0
  done < <(nmcli -g TYPE,NAME connection show | sed -n 's/^802-11-wireless://p' | sed 's/\\:/:/g')
  return 1
}

home=0
if [[ -z "$password" && -r "$secrets_wifi" ]] && ! has_profile; then
  # ENVIRON, not -v: awk -v expands backslashes in the ssid
  password=$(ssid="$ssid" awk -F'\t' '$1 == ENVIRON["ssid"] { print $2; exit }' "$secrets_wifi")
  [[ -n "$password" ]] && home=1
fi

if [[ -n "$password" ]]; then
  nmcli dev wifi connect "$ssid" password "$password"
else
  nmcli dev wifi connect "$ssid"
fi

# a saved network is home: reconnect with the hardware mac so the router's dhcp reservation holds
if ((home)); then
  nmcli connection modify "$ssid" 802-11-wireless.cloned-mac-address permanent
  nmcli connection up "$ssid"
fi
