#!/bin/env bash
#
WALLPAPER_DIR="$HOME/code/arch-dotfiles/wallpapers"
SUPPORTED_EXTENSIONS=("jpg" "jpeg" "png" "gif")

get_wallpaper_paths() {
    local files=()
    for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
        while IFS= read -r -d $'\0' file; do
            files+=("$file")
        done < <(find "$WALLPAPER_DIR" -type f -iname "*.$ext" -print0 2>/dev/null)
    done
    echo "${files[@]}"
}

get_wallpaper_filenames() {
    local wallpapers=("$@")
    local names=("Random")
    for wp in "${wallpapers[@]}"; do
        base=$(basename "${wp%.*}")
        cap_name=$(echo "$base" | sed 's/.*/\u&/')
        names+=("$cap_name")
    done
    echo "${names[@]}"
}

select_wallpaper_interactive() {
    local names=("$@")
    printf "%s\n" "${names[@]}" | wofi --dmenu --prompt="Select a wallpaper"
}

resolve_selection() {
    local selected_name="$1"
    shift
    local names=("$@")

    if [[ "$selected_name" == "Random" ]]; then
        echo "${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}"
    else
        for i in "${!names[@]}"; do
            if [[ "${names[$i]}" == "$selected_name" ]]; then
                echo "${WALLPAPERS[$((i - 1))]}"
                return
            fi
        done
    fi
}

apply_wallpaper() {
    local file="$1"
    echo "Applying wallpaper: $file"

    # set the wallpaper
    swww img "$file" --transition-type grow --transition-step 80 --transition-duration 1 --transition-fps 165 &
    ln -sf "$file" "$HOME/.cache/wal/wallpaper" 2>/dev/null || true

    # generate the new colors
    wal -i "$file"

    # generate GTK and QT themes
    themix-multi-export ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox
    themix-multi-export ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox

    # apply the new colors to other programs
    pywalfox update &
    pywal-spicetify wal &
    pywal-discord -p ~/.config/BetterDiscord/themes &

    # update hyprlock config
    sed -i "s|\$BACKGROUND = rgb([^)]*)|\$BACKGROUND = rgb($(sed -n '1p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf
    sed -i "s|\$FOREGROUND = rgb([^)]*)|\$FOREGROUND = rgb($(sed -n '2p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf
    sed -i "s|\$COLOR1 = rgb([^)]*)|\$COLOR1 = rgb($(sed -n '3p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf
    sed -i "s|\$COLOR2 = rgb([^)]*)|\$COLOR2 = rgb($(sed -n '4p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf
    sed -i "s|\$COLOR3 = rgb([^)]*)|\$COLOR3 = rgb($(sed -n '5p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf

    # update programs that need it
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    gsettings set org.gnome.desktop.interface gtk-theme '' && \
        gsettings set org.gnome.desktop.interface gtk-theme "$theme" &

    for addr in $XDG_RUNTIME_DIR/nvim.*; do
        nvim --server "$addr" --remote-send ':colorscheme pywal<CR>' &
    done

    pkill waybar && sleep 0.25 && waybar &
    pkill mako && mako &

    # notify user
    notify-send "Wallpaper changed" "New wallpaper set to: $file"
}

main() {
    WALLPAPERS=($(get_wallpaper_paths))

    # explode if no wallpapers found
    if [[ ${#WALLPAPERS[@]} -eq 0 ]]; then
        echo "No wallpapers found in $WALLPAPER_DIR"
        exit 1
    fi

    FILENAMES=($(get_wallpaper_filenames "${WALLPAPERS[@]}"))

    # use cli provided wallpaper NAME not FILE
    if [[ -n "$1" ]]; then
        SELECTED_NAME="$1"
    else
        SELECTED_NAME=$(select_wallpaper_interactive "${FILENAMES[@]}")
    fi

    # resolve and apply selection
    SELECTED_FILE=$(resolve_selection "$SELECTED_NAME" "${FILENAMES[@]}")

    if [[ -n "$SELECTED_FILE" ]]; then
        apply_wallpaper "$SELECTED_FILE"
    else
        echo "No valid wallpaper selected."
        exit 1
    fi
}

main "$@"
