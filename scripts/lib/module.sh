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

# --- nothing a person owns is ever overwritten ---
# what the dotfiles last copied to each path (path, tab, sha256): a file that differs was edited by hand or was there
# first, and is moved aside before a write. preserved copies go here, never beside the original, where a scanning dir
# (/etc/apparmor.d, systemd, autostart) would load the copy as a second config
if ((EUID == 0)); then
    DOTFILES_STATE=/var/lib/dotfiles
else
    DOTFILES_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
fi
WRITTEN_FILE="$DOTFILES_STATE/written"
PRESERVE_DIR="$DOTFILES_STATE/preserved"

# sync_guard <path>: false for any path in a syncthing folder; what lives there is the person's data, synced from
# other machines, and a file or dir made here before syncthing delivers the real one collides with it (conflicts)
sync_guard() {
    local path
    path=$(realpath -m "$1")
    case "$path" in
    /home/*/sync | /home/*/sync/* | "$HOME/sync" | "$HOME/sync"/*)
        echo "dotfiles: refusing to write $1, ~/sync belongs to syncthing" >&2
        return 1
        ;;
    esac
}

# preserve_aside <path>: moved under PRESERVE_DIR by its full path and the time, never deleted
preserve_aside() {
    local base dest n=0
    base="$PRESERVE_DIR$(realpath -ms "$1").$(date +%Y%m%d%H%M%S)"
    dest=$base
    # two in the same second must not overwrite each other
    while [[ -e "$dest" || -L "$dest" ]]; do n=$((n + 1)); dest="$base.$n"; done
    mkdir -p "$(dirname "$dest")"
    mv -n "$1" "$dest"
    echo "dotfiles: $1 was not the dotfiles' own, kept it as $dest" >&2
}

# written_hash <path>: the sha256 last copied there, empty when none
written_hash() {
    awk -F'\t' -v p="$1" '$1 == p {h = $2} END {print h}' "$WRITTEN_FILE" 2>/dev/null
}

# written_record <path>: remember what was just copied there
written_record() {
    local sum
    sum=$(sha256sum <"$1" | cut -d' ' -f1)
    mkdir -p "$DOTFILES_STATE"
    { awk -F'\t' -v p="$1" '$1 != p' "$WRITTEN_FILE" 2>/dev/null || true; printf '%s\t%s\n' "$1" "$sum"; } >"$WRITTEN_FILE.new"
    mv -f "$WRITTEN_FILE.new" "$WRITTEN_FILE"
}

# link_guard <target> <link>: make way for <link> -> <target>. a link already into the repo, to <target> or dangling
# is replaced; a real file with <target>'s exact content too; anything else (a person's file, dir or own link) is
# preserved. false only for a path in ~/sync
link_guard() {
    local target="$1" link="$2" current
    sync_guard "$link" || return 1
    if [[ -L "$link" ]]; then
        current=$(readlink "$link")
        [[ "$current" == "$target" || "$current" == "$DOTFILES"/* || "$current" == /var/lib/dotfiles/* || ! -e "$link" ]] && return 0
        preserve_aside "$link"
    elif [[ -f "$link" && -f "$target" ]] && cmp -s "$link" "$target"; then
        rm -f "$link"
    elif [[ -e "$link" ]]; then
        preserve_aside "$link"
    fi
}

# copy_guard <dest>: make way for a copy at <dest>. what the dotfiles wrote last time, untouched since, is replaced;
# a link (the older linked form) too; anything else is preserved. false only for a path in ~/sync
copy_guard() {
    local dest="$1" sum
    sync_guard "$dest" || return 1
    [[ -e "$dest" && ! -L "$dest" ]] || return 0
    sum=$(sha256sum <"$dest" | cut -d' ' -f1)
    [[ "$sum" == "$(written_hash "$dest")" ]] && return 0
    preserve_aside "$dest"
}

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
    sync_guard "$dir" || return 1
    mkdir -p "$dir"
    for file; do
        link_guard "$PWD/$file" "$dir/${file##*/}"
        ln -sfn "$PWD/$file" "$dir/${file##*/}"
    done
}

# link_as <target> <link>: <link> becomes a link to <target> under a name of its own; a same-name link goes through
# link_into, a directory through link_dir. the link's parent is made, the target is used as given ($PWD/x or absolute)
link_as() {
    link_guard "$1" "$2" || return 1
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
}

# link_dir <target> <link>: <link> becomes a link to <target>. ln -sfn onto a real directory (one an app made on its
# first start) would nest the link inside it, so that directory is preserved first, never deleted
link_dir() {
    link_guard "$1" "$2" || return 1
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
}

# link_commands <file...>: each file as a command in ~/.local/bin, named without its extension
link_commands() {
    local file base
    mkdir -p "$HOME/.local/bin"
    for file; do
        base=${file##*/}
        link_guard "$PWD/$file" "$HOME/.local/bin/${base%.*}"
        ln -sfn "$PWD/$file" "$HOME/.local/bin/${base%.*}"
    done
}

# unit_install <file...>: real copies (systemd reads them before /home mounts, root never runs a user file), one reload;
# enabling stays with the caller
unit_install() {
    local file
    for file; do
        if [[ ! -L "$UNIT_DIR/${file##*/}" ]] && cmp -s "$file" "$UNIT_DIR/${file##*/}"; then
            [[ -n "$(written_hash "$UNIT_DIR/${file##*/}")" ]] || written_record "$UNIT_DIR/${file##*/}"
            continue
        fi
        copy_guard "$UNIT_DIR/${file##*/}" || return 1
        rm -f "$UNIT_DIR/${file##*/}"
        install -Dm644 "$file" "$UNIT_DIR/${file##*/}"
        written_record "$UNIT_DIR/${file##*/}"
    done
    systemctl "$UNIT_SCOPE" daemon-reload
}

# dropin_install <unit> <conf...>: real 0644 drop-ins under <unit>.d in this scope (systemd reads them before /home
# mounts), one reload; true when any conf changed, so `dropin_install u c && try-restart u` ties a restart to a change
dropin_install() {
    local unit="$1" dir file changed=1
    shift
    dir="$UNIT_DIR/${unit}.d"
    for file; do
        file_update "$file" "$dir/${file##*/}" && changed=0
    done
    systemctl "$UNIT_SCOPE" daemon-reload
    return "$changed"
}

# unit_present <unit>: the unit file is known in this scope; an instance looks up its template
unit_present() {
    local unit="$1"
    [[ "$unit" =~ ^([^@]+@).*(\.[a-z]+)$ ]] && unit="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    systemctl "$UNIT_SCOPE" list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .
}

# file_update <src> <dest> [mode]: a real copy at <mode> (0644 default); true only when it changed (a link counts),
# so `file_update a b && restart`
file_update() {
    if [[ ! -L "$2" ]] && cmp -s "$1" "$2"; then
        # already this content: owned from now on, unchanged
        [[ -n "$(written_hash "$2")" ]] || written_record "$2"
        return 1
    fi
    copy_guard "$2" || return 1
    rm -f "$2"
    install -Dm"${3:-644}" "$1" "$2"
    written_record "$2"
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
    sed "${script[@]}" "$src" >"$dest.new" && chmod 644 "$dest.new" || return 1
    if [[ ! -L "$dest" ]] && cmp -s "$dest.new" "$dest"; then
        rm -f "$dest.new"
        [[ -n "$(written_hash "$dest")" ]] || written_record "$dest"
        return 0
    fi
    copy_guard "$dest" || { rm -f "$dest.new"; return 1; }
    mv -f "$dest.new" "$dest"
    written_record "$dest"
}

# desktop_override <id.desktop> <sed script>: a user copy of the system entry through sed, shadowing it; none without one
desktop_override() {
    local dest="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$1"
    [[ -f "$DESKTOP_SYSTEM_DIR/$1" ]] || return 0
    mkdir -p "${dest%/*}"
    sed "$2" "$DESKTOP_SYSTEM_DIR/$1" >"$dest.new"
    if [[ ! -L "$dest" ]] && cmp -s "$dest.new" "$dest"; then
        rm -f "$dest.new"
        [[ -n "$(written_hash "$dest")" ]] || written_record "$dest"
        return 0
    fi
    copy_guard "$dest" || { rm -f "$dest.new"; return 1; }
    mv -f "$dest.new" "$dest"
    written_record "$dest"
}

# java_ui_scale: the integer scale java/swing apps get, xwayland's rule from desktop/hyprland/hyprland_monitors.lua
# (1 on a laptop, else 2); keep the two in step. java would follow hyprland's GDK_SCALE, but not every launch
# path carries it and a launcher pinning sun.java2d.uiScale (ghidra) overrides it. per app, never global
java_ui_scale() {
    if [[ "${FORM_FACTOR:-}" == laptop ]]; then echo 1; else echo 2; fi
}

# desktop_java_scale <id.desktop>: that entry's Exec= under JDK_JAVA_OPTIONS carrying java_ui_scale; the java
# launcher puts it before the command line, so an app whose launcher passes its own uiScale needs that launcher's hook
desktop_java_scale() {
    desktop_override "$1" "s|^Exec=|Exec=env JDK_JAVA_OPTIONS=-Dsun.java2d.uiScale=$(java_ui_scale) |"
}

# json_update <file> <jq args...>: jq in place, {} for a missing or empty file; written back into the same inode,
# so an app holding it open or a link to it keeps working
json_update() {
    local file="$1" tmp status=0
    shift
    sync_guard "$file" || return 1
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
