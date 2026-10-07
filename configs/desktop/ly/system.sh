#!/usr/bin/env bash
# ly's binary is ly-dm (the `ly` package ships no `ly` command)

CONFIG=/etc/ly/config.ini
BACKUP="${CONFIG}.arch-dotfiles-backup"
SESSIONS=/etc/ly/sessions
SAVE=/etc/ly/save.txt
# login.defs' human uid range; build users (nixbld) in it have no login shell
UID_MIN=1000
UID_MAX=59999

# ly runs at boot before /home is mounted, so install a real file in /etc
[[ ! -e "$CONFIG" || -e "$BACKUP" ]] || install -Dm644 "$CONFIG" "$BACKUP"
install -Dm644 config.ini "$CONFIG"

# only Hyprland (uwsm) and Plasma show, next to ly's built-in shell
rm -rf "$SESSIONS"
install -Dm644 -t "$SESSIONS" sessions/hyprland.desktop sessions/plasma.desktop

# ly 1.4.1 lists the built-in shell at index 0, then crawls waylandsessions in readdir order (no sort);
# resolve Hyprland's index the same way ly will
hyprland_index=1
index=1
for session in $(ls -U "$SESSIONS"); do
    [[ "$(sed -n 's/^Name=//p' "$SESSIONS/$session" | head -1)" == Hyprland ]] && hyprland_index=$index
    index=$((index + 1))
done
# save.txt: first line is the last-used user's row, then <user>:<session index>; ly keeps known rows current (save=true),
# a user it has not seen yet (root, every human account, a later adduser-dotfiles) defaults to Hyprland
[[ -e "$SAVE" ]] || printf '1\n' >"$SAVE"
# a last row without its newline would swallow the first appended one
[[ ! -s "$SAVE" || -z "$(tail -c 1 "$SAVE")" ]] || printf '\n' >>"$SAVE"
for user in root $(awk -F: -v lo="$UID_MIN" -v hi="$UID_MAX" '$3 >= lo && $3 <= hi && $7 !~ /(nologin|false)$/ { print $1 }' /etc/passwd); do
    grep -q "^${user}:" "$SAVE" || printf '%s:%s\n' "$user" "$hyprland_index" >>"$SAVE"
done
chmod 644 "$SAVE"

# console maps ly's 24-bit colors to 16 slots; load config.ini's exact hex
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
printf '%s' "$vtrgb" >/etc/ly/vtrgb
install -Dm644 ly-palette.conf "$UNIT_DIR/ly@.service.d/palette.conf"
install -Dm644 ly-cursor.conf "$UNIT_DIR/ly@.service.d/cursor.conf"
systemctl daemon-reload

systemctl enable ly@tty2.service
systemctl disable getty@tty2.service
