#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# Switch to the next or chosen wallpaper and re-theme with wal. Single-flighted via flock.

set -euo pipefail

# Concurrency guard.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/switch-wallpaper.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # stale-lock breaker: background jobs inherit fd 9 so the lock outlives them; a real switch never nears 90s, so an older lock is stale
    if [[ -e "$LOCK_FILE" ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if (( age > 90 )); then
            echo "Stale wallpaper-switch lock (${age}s old); breaking it." >&2
            exec 9>"$LOCK_FILE.new"
            mv -f "$LOCK_FILE.new" "$LOCK_FILE"
            exec 9>"$LOCK_FILE"
            flock -n 9 || { echo "Still could not acquire lock, skipping." >&2; exit 0; }
        else
            echo "Another wallpaper switch is already in progress, skipping." >&2
            exit 0
        fi
    else
        echo "Another wallpaper switch is already in progress, skipping." >&2
        exit 0
    fi
fi

set_wallpaper() {
    local file="$1"

    # guard: a missing path would symlink wal/wallpaper to nothing and break every downstream generator
    [[ -f "$file" ]] || { echo "wallpaper not found: $file" >&2; return 1; }
    # the symlink lives in ~/.cache/wal, so a relative path (install.sh passes one) would point nowhere
    file=$(realpath "$file")

    # Background.qml refreshes over IPC only, it does not watch the symlink
    ln -sfn "$file" "$HOME/.cache/wal/wallpaper" 2>/dev/null
    echo "$file" > "$HOME/.cache/wal/wallpaper_path" 2>/dev/null

    # a dead shell reads the symlink on next start, so failure here is fine
    timeout 3 quickshell ipc -p "$HOME/.config/quickshell" \
        call background set "$file" >/dev/null 2>&1 || true

    # a theme wallpaper applies that theme's hand-authored palette instead of re-deriving one from the image
    THEME_DIR="$DOTFILES/configs/base/themes"
    FILE_REAL=$(readlink -f "$file" 2>/dev/null || echo "$file")
    THEME_JSON=""
    THEME_NAME=""
    for jf in "$THEME_DIR"/*.json; do
        [[ -e "$jf" ]] || continue
        wp=$(jq -r '.wallpaper // empty' "$jf" 2>/dev/null)
        [[ -n "$wp" ]] || continue
        wp_real=$(readlink -f "$wp" 2>/dev/null || echo "$wp")
        if [[ "$wp_real" == "$FILE_REAL" ]]; then
            THEME_JSON="$jf"
            THEME_NAME=$(basename "${jf%.json}")
            break
        fi
    done
    if [[ -n "$THEME_JSON" ]]; then
        # wallust cs regenerates every downstream template from the theme's palette
        wallust cs -s "$THEME_NAME"

        # optional per-theme font, applied through toggle-font.sh set (the one place font changes go)
        THEME_FONT=$(jq -r '.font // empty' "$THEME_JSON" 2>/dev/null)
        if [[ -n "$THEME_FONT" ]]; then
            $DOTFILES/scripts/toggles/toggle-font.sh set "$THEME_FONT" || true
        fi

        # nvim theme dispatch keys off the theme name (lua/themes/<name>.lua), else pywal
        NVIM_THEME="$THEME_NAME"
    else
        # -s skips the terminal escape sequences wallust would write to every open tty
        wallust run -s "$file"
        NVIM_THEME="pywal"
    fi
    # read by lua/theme.lua at startup and the live nvim nudge below
    printf '%s\n' "$NVIM_THEME" > "$HOME/.cache/wal/nvim_theme"

    # themix cannot init gtk without a display and config.sh runs headless in the stage service, so without a theme the first login's gtk dialogs (keyring prompt) come up in plain adwaita
    local themix=(themix-multi-export)
    if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null 2>&1; then
        themix=(xvfb-run -a themix-multi-export)
    fi
    # gtk/qt themes chained in one backgrounded subshell off the return-path critical section; timeout -k 5 because themix-multi-export can hang forever on an oomox gtk-loop bug sigterm cannot reap, and 9>&- drops the lock fd so a hung child never no-ops later switches
    ( $DOTFILES/configs/base/wallust/scripts/generate-oomox-colors.py && \
      timeout -k 5 20 "${themix[@]}" ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox 9>&- && \
      timeout -k 5 20 "${themix[@]}" ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox 9>&- ) 9>&- &

    # apply the new colors to other programs
    pywalfox update 9>&- &
    # spotify + discord colours; synchronous, the discord block below reads its output
    $DOTFILES/configs/base/wallust/scripts/generate-spicetify-colors.py
    (
      was_running=0
      pgrep -x spotify >/dev/null && was_running=1
      spicetify -n apply
      # spicetify apply renames css classes away from the dom; undo it or the client comes up stripped
      $DOTFILES/configs/socials/spotify/spicetify-unmap-classes.py || true
      pkill -x spotify
      if [ "$was_running" = 1 ]; then
        # spotify is single-instance: wait for the old process to exit before relaunching
        for _ in $(seq 20); do
          pgrep -x spotify >/dev/null || break
          sleep 0.5
        done
        setsid spotify >/dev/null 2>&1 &
      fi
    ) 9>&- &

    # hyprland does not watch ~/.cache/wal/colors, so reload it
    hyprctl reload config-only 9>&- &


    # zed and vscodium themes
    $DOTFILES/configs/base/wallust/scripts/generate-editor-themes.sh 9>&- &

    $DOTFILES/configs/base/wallust/scripts/generate-btop-theme.sh 9>&- &

    # gh-dash reads this on its next launch
    $DOTFILES/configs/base/wallust/scripts/generate-ghdash-theme.sh 9>&- &

    # caido webview, applied on its next reload via evenbetter's injected stylesheet
    $DOTFILES/configs/base/wallust/scripts/generate-caido-theme.py 9>&- >/dev/null 2>&1 &

    # telegram palette regenerates via the wal/ template; import is a manual gui step (tdesktop#31183)

    # hermes: one yaml skin themes its cli, tui and desktop app at once
    $DOTFILES/configs/base/wallust/scripts/generate-hermes-skin.py 9>&- >/dev/null 2>&1 &

    # kde/qt colours + plasma wallpaper
    $DOTFILES/configs/base/wallust/scripts/generate-kde-theme.sh "$file" 9>&- &

    # discord theme
    ui_family=$($DOTFILES/scripts/toggles/toggle-font.sh get 2>/dev/null || true)
    ui_size=$($DOTFILES/scripts/toggles/toggle-font.sh ui-size 2>/dev/null || true)
    if [[ -n "$ui_family" && "$ui_size" =~ ^[0-9]+$ ]]; then
        ui_font="$ui_family $ui_size"
    else
        ui_font=""
    fi

    # synchronous: rename-race-prone, the lock must stay held (not inherited into a background job); same conditioned palette as spotify, so the two match
    spice() { grep -m1 "^$1 " ~/.cache/wal/colors-spicetify.ini | awk '{print $3}' | sed 's/../0x& /g' | xargs printf '%d,%d,%d'; }
    rgb1=$(spice main)
    accent=$(spice button)
    raised=$(spice highlight)
    floating=$(spice main-elevated)
    text=$(spice text)
    subtext=$(spice subtext)
    # skip --font when the read failed, never write an empty `--font: ;` into the live theme
    font_expr=()
    [[ -n "$ui_family" ]] && font_expr=(-e "s|\\--font: .*$|\\--font: \"${ui_family}\";|")
    discord_theme="$HOME/.config/BetterDiscord/themes/wal.theme.css"
    if [[ -f "$discord_theme" && -n "$rgb1" && -n "$accent" ]]; then
        discord_tmp=$(mktemp)
        if sed \
            -e "s|\\--accentcolor: .*$|\\--accentcolor: ${accent};|" \
            -e "s|\\--accentcolor2: .*$|\\--accentcolor2: ${accent};|" \
            -e "s|\\--backgroundprimary: .*$|\\--backgroundprimary: ${rgb1};|" \
            -e "s|\\--backgroundsecondary: .*$|\\--backgroundsecondary: ${rgb1};|" \
            -e "s|\\--backgroundsecondaryalt: .*$|\\--backgroundsecondaryalt: ${rgb1};|" \
            -e "s|\\--backgroundtertiary: .*$|\\--backgroundtertiary: ${rgb1};|" \
            -e "s|\\--backgroundaccent: .*$|\\--backgroundaccent: ${raised};|" \
            -e "s|\\--backgroundfloating: .*$|\\--backgroundfloating: ${floating};|" \
            -e "s|\\--textbrightest: .*$|\\--textbrightest: ${text};|" \
            -e "s|\\--textbrighter: .*$|\\--textbrighter: ${text};|" \
            -e "s|\\--textdark: .*$|\\--textdark: ${subtext};|" \
            "${font_expr[@]}" \
            "$discord_theme" > "$discord_tmp" && [[ -s "$discord_tmp" ]]; then
            # same inode, so BD sees a modify rather than a delete
            cat "$discord_tmp" > "$discord_theme"
        fi
        rm -f "$discord_tmp"
    fi

    gsettings set org.gnome.desktop.interface gtk-theme 'oomox-colors-oomox'
    [[ -n "$ui_font" ]] && gsettings set org.gnome.desktop.interface font-name "$ui_font"
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    (gsettings set org.gnome.desktop.interface gtk-theme '' && gsettings set org.gnome.desktop.interface gtk-theme "$theme") 9>&- &

    # for apps that read gtk settings.ini directly, not gsettings; synchronous, last rename-race-prone step
    for gtkdir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
        mkdir -p "$gtkdir"
        ini="$gtkdir/settings.ini"
        touch "$ini"
        grep -q "^\[Settings\]" "$ini" || printf '[Settings]\n' >> "$ini"
        if grep -q "^gtk-theme-name=" "$ini"; then
            sed -i "s|^gtk-theme-name=.*|gtk-theme-name=oomox-colors-oomox|" "$ini"
        else
            sed -i "/^\[Settings\]/a gtk-theme-name=oomox-colors-oomox" "$ini"
        fi
        # skipped when the font read failed, see the guard above
        if [[ -n "$ui_font" ]]; then
            if grep -q "^gtk-font-name=" "$ini"; then
                sed -i "s|^gtk-font-name=.*|gtk-font-name=$ui_font|" "$ini"
            else
                sed -i "/^\[Settings\]/a gtk-font-name=$ui_font" "$ini"
            fi
        fi
    done

    # push the theme to every running nvim through the lua/theme.lua entry point startup uses
    for addr in "${XDG_RUNTIME_DIR:-}"/nvim.*; do
        [ -e "$addr" ] || continue
        nvim --server "$addr" --remote-send \
            "<Esc>:lua require('theme').apply('${NVIM_THEME}')<CR>" 9>&- &
    done

    # same for emacs, through the entry point its own startup uses (configs/programming/emacs/ui.el)
    if command -v emacsclient >/dev/null 2>&1; then
        timeout 5 emacsclient --eval '(my/apply-system-theme)' \
            >/dev/null 2>&1 9>&- || true &
    fi

    # re-source the tmux colours on every running server, no restart needed
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        tmux source-file ~/.cache/wal/colors-tmux.conf >/dev/null 2>&1 || true
    fi

    # kitty reloads its config on SIGUSR1
    pkill -USR1 -x kitty >/dev/null 2>&1 || true

    # ghostty has no config watcher; its reload_config action is only reachable over d-bus
    timeout 5 gdbus call --session --dest com.mitchellh.ghostty \
        --object-path /com/mitchellh/ghostty \
        --method org.gtk.Actions.Activate reload-config '[]' '{}' \
        >/dev/null 2>&1 9>&- || true &

    # no notification-daemon restart: quickshell recolours live from Commons/Color.qml

    # everything above is backgrounded so an interactive switch returns at once
    if [[ -n "${WALLPAPER_SYNC:-}" ]]; then
        wait || true
    fi
}

# fzf preview pane renders chafa over a cached vipsthumbnail jpeg (a dmenu picker is text only)
wallpaper_thumb() {
    local file="$1" thumb_dir="$HOME/.cache/wal/wallpaper-thumbs"
    mkdir -p "$thumb_dir"
    local key thumb
    key=$(stat -c '%Y-%s' "$file" 2>/dev/null)
    thumb="$thumb_dir/$(basename "$file").$key.jpg"
    if [[ ! -f "$thumb" ]]; then
        find "$thumb_dir" -name "$(basename "$file").*.jpg" -delete 2>/dev/null
        vipsthumbnail "$file" -s 480 -o "${thumb%.jpg}.jpg[Q=80]" 2>/dev/null
    fi
    [[ -f "$thumb" ]] && echo "$thumb" || echo "$file"
}
export -f wallpaper_thumb

main() {
    WALLPAPER_DIR="$DOTFILES/wallpapers"
    export WALLPAPER_DIR

    # non-interactive surface for quickshell's image-picker plugin, ahead of the fzf path
    case "${1:-}" in
    get)
        readlink -f "$HOME/.cache/wal/wallpaper" 2>/dev/null || true
        exit 0
        ;;
    list)
        find "$WALLPAPER_DIR" -type f \
            \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" \) \
            | sort
        exit 0
        ;;
    set)
        [[ -n "${2:-}" && -f "$2" ]] || { echo "usage: $(basename "$0") set <file>" >&2; exit 1; }
        set_wallpaper "$2"
        exit 0
        ;;
    esac

    WALLPAPERS="$(find "$WALLPAPER_DIR" \
        -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" \) \
        -exec basename {} \; \
        | sort)"

    # use cli provided wallpaper filepath
    if [[ -n "${1:-}" ]]; then
        if [[ ! -f "$1" && "$1" != "random" ]]; then
            echo "File does not exist: $1"
            exit 1
        fi

        if [[ "$1" == "random" ]]; then
            set_wallpaper "$WALLPAPER_DIR/$(shuf -n 1 <<< "$WALLPAPERS")"
            exit 0
        fi

        set_wallpaper "$1"
        exit 0
    fi

    # Interactive selection: the fzf preview pane renders a real thumbnail.
    SELECTED=$(printf "%s\nrandom\n" "$WALLPAPERS" | fzf \
        --prompt="wallpaper> " \
        --preview-window="right:60%" \
        --preview '
            if [[ "{}" == "random" ]]; then
                echo "(random)"
            else
                chafa --size="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}" \
                    "$(wallpaper_thumb "$WALLPAPER_DIR/{}")" 2>/dev/null
            fi
        ')

    if [[ "$SELECTED" == "CNCLD" || -z "$SELECTED" ]]; then
        echo "No wallpaper selected."
        exit 0
    fi

    if [[ "$SELECTED" == "random" ]]; then
        SELECTED_FILE="$WALLPAPER_DIR/$(shuf -n 1 <<< "$WALLPAPERS")"
    else
        SELECTED_FILE="$WALLPAPER_DIR/$SELECTED"
    fi

    set_wallpaper "$SELECTED_FILE"
    exit 0
}

main "$@"
