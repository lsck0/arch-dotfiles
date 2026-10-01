#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# ly's binary is ly-dm (the `ly` package ships no `ly` command)
if ! command -v ly-dm >/dev/null 2>&1; then
    exit 0
fi

set -e

# ly runs at boot before /home is mounted, so install a real file in /etc
config=/etc/ly/config.ini
backup="${config}.arch-dotfiles-backup"
if [[ -e "$config" && ! -e "$backup" ]]; then
    sudo install -Dm644 "$config" "$backup"
fi

sudo install -Dm644 config.ini "$config"

# the kernel console maps ly's 24-bit colors onto its 16-slot palette (fg 0x39BAE6 lands on bright cyan),
# so load slots that hold config.ini's exact colors; grub's theme draws the same hex values
palette=(
    0b0e14 f07178 aad94c e6b450 39bae6 d2a6ff 1c6e8c bfbdb6
    565b66 f07178 aad94c e6b450 39bae6 d2a6ff 39bae6 bfbdb6
)
vtrgb=""
for offset in 0 2 4; do
    row=()
    for color in "${palette[@]}"; do row+=("$((16#${color:offset:2}))"); done
    vtrgb+="$(IFS=,; echo "${row[*]}")"$'\n'
done
printf '%s' "$vtrgb" | sudo tee /etc/ly/vtrgb >/dev/null
sudo install -Dm644 ly-palette.conf /etc/systemd/system/ly@.service.d/palette.conf
sudo systemctl daemon-reload
