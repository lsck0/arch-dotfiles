#!/bin/env bash
#
set_wallpaper() {
    local file="$1"

    # set the wallpaper
    swww img "$file" --transition-type center --transition-step 1 --transition-duration 5 --transition-fps 60 &
    ln -sf "$file" "$HOME/.cache/wal/wallpaper" 2>/dev/null &

    # generate the new colors
    wal -i "$file"

    # generate GTK and QT themes
    themix-multi-export ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox
    themix-multi-export ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox

    # apply the new colors to other programs
    pywalfox update &
    pywal-spicetify wal &

    # update discord theme
    sed -i "s|\--accentcolor: .*$|\--accentcolor: $(sed -n '2p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--accentcolor2: .*$|\--accentcolor2: $(sed -n '2p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundprimary: .*$|\--backgroundprimary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundsecondary: .*$|\--backgroundsecondary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundsecondaryalt: .*$|\--backgroundsecondaryalt: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundtertiary: .*$|\--backgroundtertiary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css &

    # update hyprlock config
    sed -i "s|\$BACKGROUND = rgb([^)]*)|\$BACKGROUND = rgb($(sed -n '1p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$FOREGROUND = rgb([^)]*)|\$FOREGROUND = rgb($(sed -n '2p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR1 = rgb([^)]*)|\$COLOR1 = rgb($(sed -n '3p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR2 = rgb([^)]*)|\$COLOR2 = rgb($(sed -n '4p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR3 = rgb([^)]*)|\$COLOR3 = rgb($(sed -n '5p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf &

    # update programs that need it
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    gsettings set org.gnome.desktop.interface gtk-theme '' && gsettings set org.gnome.desktop.interface gtk-theme "$theme" &

    for addr in $XDG_RUNTIME_DIR/nvim.*; do
        nvim --server "$addr" --remote-send ':colorscheme pywal<CR>' &
    done

    # touch the waybar style to have it reload (it doesnt detect dependencies of style.css)
    echo "" >> ~/.config/waybar/style.css && sed -i '${/^$/d;}' ~/.config/waybar/style.css &

    pkill mako && mako &
}

main() {
    WALLPAPER_DIR="$HOME/code/arch-dotfiles/wallpapers"

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

    # select wallpaper interactively
    SELECTED=$(printf "%s\nrandom\n" "$WALLPAPERS" | walker --stream --dmenu)

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

    # wait in case something takes longer than instantly
    sleep 5

    exit 0
}

main "$@"
