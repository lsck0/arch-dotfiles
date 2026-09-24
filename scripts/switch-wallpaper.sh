#!/usr/bin/env bash

# Concurrency guard.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/switch-wallpaper.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # Self-healing: background jobs spawned below (themix-multi-export, pywalfox, etc.) inherit this fd, so the lock is intentionally held until all of them finish, not just the synchronous prologue — that's what actually closes the inode-rename race across two whole invocations, not just their fast paths. The failure mode that bites is a background job that HANGS rather than exits: it holds fd 9 forever and every future switch silently no-ops. This has already happened for real — themix-multi-export enters an infinite GTK idle loop (never reaching its own app.quit()) when it hits a certain upstream oomox bug (IsADirectoryError inside an exception handler that never unblocks the main loop; see the `timeout` wrapped around it below, which is the actual fix for the hang itself). This mtime check is the safety net for the NEXT thing that hangs in a way nobody anticipated: a switch legitimately never takes anywhere near 90s end-to-end (slowest steps are ~1.5s each and run in parallel), so a lock older than that is unambiguously stale, not just slow.
    if [[ -e "$LOCK_FILE" ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if (( age > 90 )); then
            echo "Stale wallpaper-switch lock (${age}s old) — breaking it." >&2
            exec 9>"$LOCK_FILE.new"
            mv -f "$LOCK_FILE.new" "$LOCK_FILE"
            exec 9>"$LOCK_FILE"
            flock -n 9 || { echo "Still couldn't acquire lock — skipping." >&2; exit 0; }
        else
            echo "Another wallpaper switch is already in progress — skipping." >&2
            exit 0
        fi
    else
        echo "Another wallpaper switch is already in progress — skipping." >&2
        exit 0
    fi
fi

set_wallpaper() {
    local file="$1"

    # Background.qml refreshes on startup or over IPC only — it does not watch the symlink — so the shell has to be told, not just pointed at the file.
    ln -sfn "$file" "$HOME/.cache/wal/wallpaper" 2>/dev/null
    echo "$file" > "$HOME/.cache/wal/wallpaper_path" 2>/dev/null

    # A dead shell just reads the symlink on its next start, so failure here is not worth reporting.
    timeout 3 quickshell ipc -p "$HOME/.config/quickshell" \
        call background set "$file" >/dev/null 2>&1 || true

    # A theme wallpaper is a handwritten theme's own background: selecting one must apply that theme's hand-authored palette rather than re-derive a palette from the image.
    THEME_DIR="$HOME/projects/arch-dotfiles/themes"
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
        # `wallust cs` regenerates every downstream template (ghostty, kitty, tmux, hyprlock's colors-rgb, …) from the theme's palette; copying colors.json alone would leave all of them stale.
        wallust cs -s "$THEME_NAME"

        # Optional per-theme "font" field, applied through toggle-font.sh's own `set` — the single place every font change in this repo goes through.
        THEME_FONT=$(jq -r '.font // empty' "$THEME_JSON" 2>/dev/null)
        if [[ -n "$THEME_FONT" ]]; then
            ~/projects/arch-dotfiles/toggles/toggle-font.sh set "$THEME_FONT" || true
        fi

        # nvim's theme dispatch keys off the theme's own name (lua/themes/ <name>.lua), falling back to pywal inside lua/theme.lua when there is no matching file.
        NVIM_THEME="$THEME_NAME"
    else
        # -s skips terminal escape sequences, which wallust would otherwise write to every open TTY.
        wallust run -s "$file"
        NVIM_THEME="pywal"
    fi
    # Read by lua/theme.lua at startup, and by the live nvim nudge below.
    printf '%s\n' "$NVIM_THEME" > "$HOME/.cache/wal/nvim_theme"

    # GTK/Qt themes.
    ~/projects/arch-dotfiles/configs/wallust/scripts/generate-oomox-colors.py || true

    # `timeout` + `9>&-`: themix-multi-export has a real upstream bug (three of its export layout entries — qt5ct, qt6ct, gtk4-oodwaita — used to ship a bare "~" default_path; fixed in configs/oomox/*.json, but kept defensive here since it's an upstream bug, not ours, and could regress if the export layout is ever regenerated from the GUI). Before that fix, the plugin's os.path.isdir("~") check always failed (unexpanded tilde), so it fell through to writing straight over the home directory -> IsADirectoryError raised inside a GTK idle callback that never reaches the CLI's own app.quit() — the process hangs forever instead of exiting. `timeout` bounds that. `9>&-` closes this invocation's lock fd in the child: background jobs inherit open fds by default, so without this a themix process that outlives the script (hung OR just slow) would hold the flock open indefinitely and wedge every subsequent wallpaper switch — exactly what `timeout` guards against for hangs, `9>&-` guards against for the ordinary case of "still running after the parent script's own critical section is done and it moved on". Every background job below gets the same treatment for the same reason — importantly including pywal-spicetify, which actually RESTARTS Spotify as a side effect: that new Spotify process is long-lived (stays open for the rest of the desktop session) and would otherwise hold this invocation's lock open for hours, silently no-opping every wallpaper switch after it. This is not hypothetical — it happened for real in production use. -k 5: SIGTERM alone doesn't reap this hang (wedged in a GTK main-loop iteration, so CPython never runs the handler). 42 survivors seen.
    timeout -k 5 20 themix-multi-export ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox 9>&- &
    timeout -k 5 20 themix-multi-export ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox 9>&- &

    # apply the new colors to other programs
    pywalfox update 9>&- &
    # pywal-spicetify launches/restarts Spotify to patch it (see the flock comment above this block).
    (
      was_running=0
      pgrep -x spotify >/dev/null && was_running=1
      ~/projects/arch-dotfiles/configs/wallust/scripts/generate-spicetify-colors.py && pywal-spicetify wal
      # pywal-spicetify runs `spicetify apply`, which renames the client's CSS classes away from what the DOM uses; undo that and reload the client it just started, or it comes up with the layout stripped.
      ~/projects/arch-dotfiles/configs/spotify/spicetify-unmap-classes.py || true
      pkill -x spotify
      if [ "$was_running" = 1 ]; then
        # Spotify is single-instance: a new process started while the old one still holds the lock exits immediately and leaves nothing running, so wait for the old one to actually be gone before relaunching.
        for _ in $(seq 20); do
          pgrep -x spotify >/dev/null || break
          sleep 0.5
        done
        setsid spotify >/dev/null 2>&1 &
      fi
    ) 9>&- &

    # The lua config reads ~/.cache/wal/colors itself, and hyprland does not watch that file.
    hyprctl reload config-only 9>&- &

    # update hyprlock config.
    sed -i "s|\$BACKGROUND = rgb([^)]*)|\$BACKGROUND = rgb($(sed -n '1p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$FOREGROUND = rgb([^)]*)|\$FOREGROUND = rgb($(sed -n '2p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR1 = rgb([^)]*)|\$COLOR1 = rgb($(sed -n '3p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR2 = rgb([^)]*)|\$COLOR2 = rgb($(sed -n '4p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR3 = rgb([^)]*)|\$COLOR3 = rgb($(sed -n '5p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$BACKGROUND_GLASS = rgba([^)]*)|\$BACKGROUND_GLASS = rgba($(sed -n '1p' ~/.cache/wal/colors-rgb),0.55)|" ~/.config/hypr/hyprlock.conf

    # update zed and vscodium themes
    ~/projects/arch-dotfiles/configs/wallust/scripts/generate-editor-themes.sh 9>&- &

    # No chat-client theming: Telegram needs a manual GUI confirmation for a palette file (tdesktop#31183), ZapZap hardcodes its palette, and Signal exposes no theming hook at all.

    # Hermes agent: one YAML skin themes its CLI, TUI and desktop app at once, so this rewrites a single file rather than driving three integrations.
    ~/projects/arch-dotfiles/configs/wallust/scripts/generate-hermes-skin.py 9>&- >/dev/null 2>&1 &

    # KDE/Qt colours + Plasma's wallpaper.
    ~/projects/arch-dotfiles/configs/wallust/scripts/generate-kde-theme.sh "$file" 9>&- &

    # update discord theme.
    ui_family=$(~/projects/arch-dotfiles/toggles/toggle-font.sh get 2>/dev/null || true)
    ui_size=$(~/projects/arch-dotfiles/toggles/toggle-font.sh ui-size 2>/dev/null || true)
    if [[ -n "$ui_family" && "$ui_size" =~ ^[0-9]+$ ]]; then
        ui_font="$ui_family $ui_size"
    else
        ui_font=""
    fi

    # SYNCHRONOUS — see the hyprlock.conf comment above for why: this is the other rename-race-prone step, and the lock must stay held for it, not get inherited into a background job.
    rgb1=$(sed -n '1p' ~/.cache/wal/colors-rgb)
    rgb2=$(sed -n '2p' ~/.cache/wal/colors-rgb)
    # --font stays untouched (no -e for it) when the read above failed, same "leave it alone" rule as gtk-font-name below — never write an empty `--font: ;` into the live BetterDiscord theme.
    font_expr=()
    [[ -n "$ui_family" ]] && font_expr=(-e "s|\\--font: .*$|\\--font: \"${ui_family}\";|")
    discord_theme="$HOME/.config/BetterDiscord/themes/wal.theme.css"
    if [[ -f "$discord_theme" ]]; then
        discord_tmp=$(mktemp)
        if sed \
            -e "s|\\--accentcolor: .*$|\\--accentcolor: ${rgb2};|" \
            -e "s|\\--accentcolor2: .*$|\\--accentcolor2: ${rgb2};|" \
            -e "s|\\--backgroundprimary: .*$|\\--backgroundprimary: ${rgb1};|" \
            -e "s|\\--backgroundsecondary: .*$|\\--backgroundsecondary: ${rgb1};|" \
            -e "s|\\--backgroundsecondaryalt: .*$|\\--backgroundsecondaryalt: ${rgb1};|" \
            -e "s|\\--backgroundtertiary: .*$|\\--backgroundtertiary: ${rgb1};|" \
            "${font_expr[@]}" \
            "$discord_theme" > "$discord_tmp" && [[ -s "$discord_tmp" ]]; then
            # Same inode, so BD sees a modify rather than a delete.
            cat "$discord_tmp" > "$discord_theme"
        fi
        rm -f "$discord_tmp"
    fi

    gsettings set org.gnome.desktop.interface gtk-theme 'oomox-colors-oomox'
    [[ -n "$ui_font" ]] && gsettings set org.gnome.desktop.interface font-name "$ui_font"
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    (gsettings set org.gnome.desktop.interface gtk-theme '' && gsettings set org.gnome.desktop.interface gtk-theme "$theme") 9>&- &

    # apps that read gtk-3.0/gtk-4.0 settings.ini directly instead of gsettings (nwg-look used to be a manual step for exactly this) SYNCHRONOUS — third and last of the rename-race-prone `sed -i` steps; see the hyprlock.conf comment above.
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
        # Skipped when the font read failed — see the guard above.
        if [[ -n "$ui_font" ]]; then
            if grep -q "^gtk-font-name=" "$ini"; then
                sed -i "s|^gtk-font-name=.*|gtk-font-name=$ui_font|" "$ini"
            else
                sed -i "/^\[Settings\]/a gtk-font-name=$ui_font" "$ini"
            fi
        fi
    done

    # Push the active theme to every running nvim through the same lua/theme.lua entry point startup uses, so open buffers recolour exactly as a fresh launch would.
    for addr in $XDG_RUNTIME_DIR/nvim.*; do
        nvim --server "$addr" --remote-send \
            "<Esc>:lua require('theme').apply('${NVIM_THEME}')<CR>" 9>&- &
    done

    # Same idea for emacs, through the entry point its own startup uses (configs/emacs/ui.el).
    if command -v emacsclient >/dev/null 2>&1; then
        timeout 5 emacsclient --eval '(my/apply-system-theme)' \
            >/dev/null 2>&1 || true
    fi

    # Re-source the generated tmux colours on every running server, so open sessions recolour without a restart.
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        tmux source-file ~/.cache/wal/colors-tmux.conf >/dev/null 2>&1 || true
    fi

    # kitty reloads its config on SIGUSR1; without this an open kitty keeps the old palette even though colors-kitty.conf was regenerated.
    pkill -USR1 -x kitty >/dev/null 2>&1 || true

    # Ghostty has no config-file watcher, so touching its config does nothing; its reload_config action is only reachable over D-Bus.
    timeout 5 gdbus call --session --dest com.mitchellh.ghostty \
        --object-path /com/mitchellh/ghostty \
        --method org.gtk.Actions.Activate reload-config '[]' '{}' \
        >/dev/null 2>&1 || true

    # No notification-daemon restart: quickshell's notifications plugin recolours live from Commons/Color.qml, which watches colors.json itself.

    # Everything above is backgrounded so an interactive switch returns at once.
    if [[ -n "${WALLPAPER_SYNC:-}" ]]; then
        wait || true
    fi
}

# A dmenu-style picker is plain text only, so the interactive picker below uses fzf's preview pane with chafa over a cached vipsthumbnail JPEG instead.
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
    WALLPAPER_DIR="$HOME/projects/arch-dotfiles/wallpapers"
    export WALLPAPER_DIR

    # Non-interactive surface for the native picker (quickshell's image-picker plugin), ahead of the fzf path so the panel never has to know about fzf.
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
        | sort)\
    "

    # use cli provided wallpaper filepath
    if [[ -n "$1" ]]; then
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
