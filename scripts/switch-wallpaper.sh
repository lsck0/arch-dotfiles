#!/bin/env bash
#
WALLPAPER_DIR="$HOME/code/arch-dotfiles/wallpapers/"
WALLPAPERS=($(ls "$WALLPAPER_DIR"/*.{jpg,jpeg,png,gif} 2> /dev/null))

# build the list
FILENAMES=("Random")
for WALLPAPER in "${WALLPAPERS[@]}"; do
    BASENAME=$(basename "$WALLPAPER")
    FILENAME_WITHOUT_EXT="${BASENAME%.*}"
    CAPITALIZED_NAME=$(echo "$FILENAME_WITHOUT_EXT" | sed 's/.*/\u&/')
    FILENAMES+=("$CAPITALIZED_NAME")
done

# explode if no wallpapers
if [ ${#WALLPAPERS[@]} -eq 0 ]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

# ask for selection
SELECTED_NAME=$(printf "%s\n" "${FILENAMES[@]}" | wofi --dmenu --prompt="Select a wallpaper")

# do the selection
if [ "$SELECTED_NAME" == "Random" ]; then
    SELECTED=${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}
else
    for i in "${!FILENAMES[@]}"; do
        if [ "${FILENAMES[$i]}" == "$SELECTED_NAME" ]; then
            SELECTED="${WALLPAPERS[$i-1]}"
            break
        fi
    done
fi

if [ -n "$SELECTED" ]; then
    # set the wallpaper
    swww img "$SELECTED" --transition-type grow --transition-step 80 --transition-duration 1 --transition-fps 165 &

    # generate the new colors
    wal -i "$SELECTED"

    # generate gtk and qt themes
    themix-multi-export ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox
    themix-multi-export ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox

    # apply the new colors to other programs
    pywalfox update &
    pywal-spicetify wal &
    pywal-discord -p ~/.config/BetterDiscord/themes &

    # update programs that need it
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    gsettings set org.gnome.desktop.interface gtk-theme '' && \
        gsettings set org.gnome.desktop.interface gtk-theme $theme &

    for addr in $XDG_RUNTIME_DIR/nvim.*; do
        nvim --server $addr --remote-send ':colorscheme pywal<CR>' &
    done

    pkill waybar && waybar &
    pkill mako && mako &

    # notify
    notify-send "Wallpaper changed" "New wallpaper set to: $SELECTED"
fi
