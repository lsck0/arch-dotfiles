# shellcheck shell=bash
# sourced by every module process (module_run) and by both drivers: the libraries plus the helpers modules share.
# root gets the system scope (/etc, system units), anyone else the user scope ($HOME, user units); see configs/*/*/{system,link}.sh

MODULE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_LIB_DIR/secrets.sh"
source "$MODULE_LIB_DIR/fetch.sh"
source "$MODULE_LIB_DIR/user-hook.sh"
source "$MODULE_LIB_DIR/profile.sh"
source "$MODULE_LIB_DIR/system.sh"

DESKTOP_SYSTEM_DIR=/usr/share/applications
if ((EUID == 0)); then
    UNIT_SCOPE=--system
    UNIT_DIR=/etc/systemd/system
else
    UNIT_SCOPE=--user
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    profile_load
fi

# module_run <script>: one link.sh/system.sh (or link.py) in its own dir under bash -e with this file sourced, stdin
# /dev/null, output also in <script>.log; the module's status, not tee's
module_run() {
    local dir name
    dir=$(dirname "$1")
    name=$(basename "$1")
    (
        set -o pipefail
        cd "$dir" || exit 1
        if [[ "$name" == *.py ]]; then
            python "./$name"
        else
            # shellcheck disable=SC2016
            bash -ec 'source "$DOTFILES/scripts/lib/module.sh" && source "$0"' "./$name"
        fi </dev/null 2>&1 | tee "$name.log"
    )
}

# link_into <dir> <file...>: link each file of the module dir into <dir> under its own name
link_into() {
    local dir="$1" file
    shift
    mkdir -p "$dir"
    for file; do ln -sfn "$PWD/$file" "$dir/${file##*/}"; done
}

# link_commands <file...>: each file as a command in ~/.local/bin, named without its extension
link_commands() {
    local file base
    mkdir -p "$HOME/.local/bin"
    for file; do
        base=${file##*/}
        ln -sfn "$PWD/$file" "$HOME/.local/bin/${base%.*}"
    done
}

# unit_install <file...>: real copies (systemd reads them before /home mounts, root never runs a user file), one reload;
# enabling stays with the caller
unit_install() {
    local file
    for file; do
        rm -f "$UNIT_DIR/${file##*/}"
        install -Dm644 "$file" "$UNIT_DIR/${file##*/}"
    done
    systemctl "$UNIT_SCOPE" daemon-reload
}

# unit_present <unit>: the unit file is known in this scope; an instance looks up its template
unit_present() {
    local unit="$1"
    [[ "$unit" =~ ^([^@]+@).*(\.[a-z]+)$ ]] && unit="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    systemctl "$UNIT_SCOPE" list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .
}

# file_update <src> <dest>: a real 0644 copy; true only when it changed (a link counts), so `file_update a b && restart`
file_update() {
    [[ -L "$2" ]] || ! cmp -s "$1" "$2" || return 1
    rm -f "$2"
    install -Dm644 "$1" "$2"
}

# file_render <src> <dest> <KEY=value...>: <src> with every @KEY@ replaced, renamed into place 0644
file_render() {
    local src="$1" dest="$2" pair value
    local -a script=(-e '')
    shift 2
    for pair; do
        value=$(printf '%s' "${pair#*=}" | sed 's/[\\|&]/\\&/g')
        script+=(-e "s|@${pair%%=*}@|$value|g")
    done
    mkdir -p "$(dirname "$dest")"
    sed "${script[@]}" "$src" >"$dest.new" && chmod 644 "$dest.new" && mv -f "$dest.new" "$dest"
}

# desktop_override <id.desktop> <sed script>: a user copy of the system entry through sed, shadowing it; none without one
desktop_override() {
    local dest="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$1"
    [[ -f "$DESKTOP_SYSTEM_DIR/$1" ]] || return 0
    mkdir -p "${dest%/*}"
    sed "$2" "$DESKTOP_SYSTEM_DIR/$1" >"$dest"
}

# json_update <file> <jq args...>: jq in place, {} for a missing or empty file; written back into the same inode,
# so an app holding it open or a link to it keeps working
json_update() {
    local file="$1" tmp status=0
    shift
    mkdir -p "$(dirname "$file")"
    [[ -s "$file" ]] || echo '{}' >"$file"
    tmp=$(mktemp)
    jq "$@" "$file" >"$tmp" && cat "$tmp" >"$file" || status=$?
    rm -f "$tmp"
    return "$status"
}

# group_add_admins <group>: a system group every wheel member is in; a later admin joins on the next config run
group_add_admins() {
    local member
    local -a members=()
    getent group "$1" >/dev/null || groupadd -r "$1"
    IFS=, read -ra members <<<"$(getent group wheel | cut -d: -f4)"
    for member in "${members[@]}"; do gpasswd -a "$member" "$1" >/dev/null; done
}
