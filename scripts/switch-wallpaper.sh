#!/usr/bin/env bash
# Wallpaper: pick one, render it, and regenerate every theme derived from it.
#
# Also the backend for quickshell's native picker, via the get/list/set
# subcommands below — the panel drives this rather than duplicating the pywal
# logic in QML.
#
# THE RENDERER IS QUICKSHELL, NOT awww (changed 2026-09-02). Two wallpaper
# renderers used to run at once: `awww-daemon` and quickshell's own QML
# crossfade in plugins/background/Background.qml, which watches
# ~/.cache/wal/wallpaper (the symlink written below) and does its own
# reveal animation. Two renderers on the same surface is a z-order race, and
# awww's transition flags were doing work nobody saw.
#
# Tradeoff, deliberate: with awww gone the wallpaper is painted by quickshell
# alone, so a dead shell means no wallpaper. That is already true of the bar,
# the notifications and the OSD.

set_wallpaper() {
    local file="$1"

    # Update the symlink pywal reads, then TELL the shell. Background.qml
    # refreshes on Component.onCompleted or over IPC only — it does not watch
    # the symlink — so without this push the wallpaper silently would not
    # change until the next shell restart. That went unnoticed while
    # awww-daemon was painting on top of it.
    ln -sf "$file" "$HOME/.cache/wal/wallpaper" 2>/dev/null
    echo "$file" > "$HOME/.cache/wal/wallpaper_path" 2>/dev/null

    # `set` crossfades; a dead shell just means the next start reads the
    # symlink itself, so failure here is not worth reporting.
    timeout 3 quickshell ipc -p "$HOME/.config/quickshell" \
        call background set "$file" >/dev/null 2>&1 || true

    # generate the new colors. wallust replaced pywal 2026-09-03 — see
    # configs/wallust/wallust.toml. Every consumer still reads ~/.cache/wal/*,
    # so this one line is the whole engine swap.
    #
    # A THEME WALLPAPER (themes/wallpapers/) is a
    # handwritten theme's own background, derived from its palette. Selecting
    # one must apply the theme's hand-authored colors.json, NOT re-derive from
    # the image (which would throw away the handwriting).
    #
    # Matched by each theme JSON's own "wallpaper" field (authoritative),
    # not by filename convention — a theme JSON and its wallpaper no longer
    # need matching basenames. Cheap enough as a linear jq scan: eleven
    # themes, once per wallpaper switch.
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
        # `wallust cs` regenerates every downstream template (ghostty.conf,
        # colors-kitty.conf, colors-tmux.conf, hyprlock's colors-rgb, etc.)
        # from the theme's hand-authored palette. A plain `cp colors.json`
        # only updated that one file, leaving ghostty/kitty/tmux on stale
        # colors. The theme is registered in wallust's colorschemes dir by
        # configs/wallust/link.sh; `-s` skips terminal escape sequences.
        wallust cs -s "$THEME_NAME"

        # Each theme JSON can carry its own "font" field (added 2026-09-09;
        # every theme currently ships "0xProto Nerd Font", matching the
        # previous hardcoded default — the field exists so a theme CAN
        # diverge, not because any does yet). Goes through toggle-font.sh's
        # own `set`, the same single place every other font change in this
        # repo goes through (apply_family + is_installed guard + reload
        # nudges) — this must not duplicate that logic here.
        THEME_FONT=$(jq -r '.font // empty' "$THEME_JSON" 2>/dev/null)
        if [[ -n "$THEME_FONT" ]]; then
            ~/projects/arch-dotfiles/toggles/toggle-font.sh set "$THEME_FONT" || true
        fi

        # Nvim's theme dispatch (lua/theme.lua + lua/themes/*.lua) keys
        # directly off the theme's own name, one file per theme — no mapping
        # table here anymore. A THEME_NAME with no matching lua/themes/<name>.lua
        # falls back to pywal inside lua/theme.lua itself, same as the
        # marker-missing case.
        NVIM_THEME="$THEME_NAME"
    else
        # -s skips terminal escape sequences: wallust would otherwise write
        # them to every open TTY, and this runs in the background from a
        # keybind.
        wallust run -s "$file"
        NVIM_THEME="pywal"
    fi
    # The active theme name, read by lua/theme.lua (startup) and the live
    # nvim nudge below.
    printf '%s\n' "$NVIM_THEME" > "$HOME/.cache/wal/nvim_theme"

    # generate GTK and QT themes. Backgrounded like everything else below —
    # these two were the actual source of "color switching feels slow":
    # ~1.5s each, ~3.3s combined, run synchronously back-to-back while nothing
    # else in this function even started. Nothing downstream has a hard
    # ordering dependency on them finishing first (the gsettings GTK-theme
    # toggle below already races other backgrounded generators, e.g.
    # generate-kde-theme.sh, the same way) — worst case GTK apps pick up the
    # new colors a moment after terminal apps do, self-correcting once these
    # finish, not a lasting bug.
    # colors-oomox is generated HERE, not by a wallust template any more.
    # The template mapped GTK theme roles to fixed palette slots
    # (SEL_FG={color0} on SEL_BG={color1}, and so on), which produced
    # near-black text on a mid-tone selection bar and sub-3:1 buttons —
    # reported as "nemo is nearly black on a medium bright background".
    # pywal-syntax templates have no colour maths, so the fix cannot live in
    # one. This runs SYNCHRONOUSLY and before both exporters, because they
    # read the file it writes.
    ~/projects/arch-dotfiles/scripts/generate-oomox-colors.py || true

    themix-multi-export ~/.config/oomox/export_config/multi_export_oomox_classic.json ~/.cache/wal/colors-oomox &
    themix-multi-export ~/.config/oomox/export_config/multi_export_oodwaita.json ~/.cache/wal/colors-oomox &

    # apply the new colors to other programs
    pywalfox update &
    pywal-spicetify wal &

    # the lua config reads ~/.cache/wal/colors itself, and hyprland does not
    # watch that file the way it used to watch the sourced colors-hyprland.conf
    # config-only: skip the monitor reload, it flickers the outputs
    hyprctl reload config-only &

    # update hyprlock config
    sed -i "s|\$BACKGROUND = rgb([^)]*)|\$BACKGROUND = rgb($(sed -n '1p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$FOREGROUND = rgb([^)]*)|\$FOREGROUND = rgb($(sed -n '2p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR1 = rgb([^)]*)|\$COLOR1 = rgb($(sed -n '3p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR2 = rgb([^)]*)|\$COLOR2 = rgb($(sed -n '4p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    sed -i "s|\$COLOR3 = rgb([^)]*)|\$COLOR3 = rgb($(sed -n '5p' ~/.cache/wal/colors-rgb))|" ~/.config/hypr/hyprlock.conf && \
    # Same triple as $BACKGROUND above, alpha left untouched — only the RGB
    # part tracks the wallpaper, the 0.55 translucency is a fixed design
    # choice for the input-field's frosted-glass look.
    sed -i "s|\$BACKGROUND_GLASS = rgba([^)]*)|\$BACKGROUND_GLASS = rgba($(sed -n '1p' ~/.cache/wal/colors-rgb),0.55)|" ~/.config/hypr/hyprlock.conf &

    # walker's CSS was regenerated here until 2026-09-02. walker is gone;
    # its two dmenu call sites moved to scripts/picker.sh, which reads
    # ~/.cache/wal/colors at call time and so needs no regeneration step.

    # update zed and vscodium themes
    ~/projects/arch-dotfiles/scripts/generate-editor-themes.sh &

    # Chat client theming (Telegram/ZapZap/Signal) was attempted and dropped
    # 2026-09-08: Telegram has no CLI/D-Bus way to apply a .tdesktop-palette
    # file (upstream feature request tdesktop#31183, still open), so it
    # needed a manual one-time GUI confirmation click that defeats the point
    # of automatic theming; ZapZap's palette is hardcoded in site-packages;
    # Signal is Electron with no theming hook at all. Not worth maintaining.
    # See git history for scripts/generate-chat-themes.sh if revisiting.

    # Hermes agent. One YAML skin themes its CLI, TUI and desktop app at once
    # (its gateway pushes the resolved skin to every surface), so this is a
    # single file rather than three integrations. Already activated once; this
    # just rewrites the file the active skin points at.
    ~/projects/arch-dotfiles/scripts/generate-hermes-skin.py >/dev/null 2>&1 &

    # update KDE/Qt colours + Plasma's own wallpaper. Qt apps (qutebrowser,
    # obs, proton-vpn-qt-app) reach this through QT_QPA_PLATFORMTHEME=kde ->
    # plasma-integration -> ~/.config/kdeglobals.
    ~/projects/arch-dotfiles/scripts/generate-kde-theme.sh "$file" &

    # update discord theme
    sed -i "s|\--accentcolor: .*$|\--accentcolor: $(sed -n '2p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--accentcolor2: .*$|\--accentcolor2: $(sed -n '2p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundprimary: .*$|\--backgroundprimary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundsecondary: .*$|\--backgroundsecondary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundsecondaryalt: .*$|\--backgroundsecondaryalt: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css && \
    sed -i "s|\--backgroundtertiary: .*$|\--backgroundtertiary: $(sed -n '1p' ~/.cache/wal/colors-rgb);|" ~/.config/BetterDiscord/themes/wal.theme.css &

    # update programs that need it
    #
    # The font is READ from toggles/toggle-font.sh, not hardcoded. It used to
    # be a literal '0xProto Nerd Font 10' here and in the settings.ini loop
    # below, which meant a wallpaper switch silently reset the desktop font
    # back to 0xProto — undoing any font change the moment the wallpaper
    # changed. This script owns colours; it must not own the font.
    # Guarded, and the guard is the point: if either read fails or comes back
    # empty, `ui_font` would be "<family> " or " 10" and the sed below would
    # write that straight into both settings.ini files and gsettings. A
    # wallpaper switch must not be able to break the desktop font, so a bad
    # read means "leave the font alone" rather than "write half of one".
    ui_family=$(~/projects/arch-dotfiles/toggles/toggle-font.sh get 2>/dev/null || true)
    ui_size=$(~/projects/arch-dotfiles/toggles/toggle-font.sh ui-size 2>/dev/null || true)
    if [[ -n "$ui_family" && "$ui_size" =~ ^[0-9]+$ ]]; then
        ui_font="$ui_family $ui_size"
    else
        ui_font=""
    fi

    gsettings set org.gnome.desktop.interface gtk-theme 'oomox-colors-oomox'
    [[ -n "$ui_font" ]] && gsettings set org.gnome.desktop.interface font-name "$ui_font"
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    gsettings set org.gnome.desktop.interface gtk-theme '' && gsettings set org.gnome.desktop.interface gtk-theme "$theme" &

    # apps that read gtk-3.0/gtk-4.0 settings.ini directly instead of
    # gsettings (nwg-look used to be a manual step for exactly this)
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
        # Skipped entirely when the font read failed — see the guard above.
        if [[ -n "$ui_font" ]]; then
            if grep -q "^gtk-font-name=" "$ini"; then
                sed -i "s|^gtk-font-name=.*|gtk-font-name=$ui_font|" "$ini"
            else
                sed -i "/^\[Settings\]/a gtk-font-name=$ui_font" "$ini"
            fi
        fi
    done &

    # Push the active theme to every running nvim. Reads the marker written
    # above (the theme's own name for theme wallpapers, "pywal" for photo
    # wallpapers) and calls the exact same lua/theme.lua entry point startup
    # uses, so a live theme switch recolors open buffers identically to a
    # fresh nvim launch. Single-quoted Lua string literal built directly —
    # NVIM_THEME only ever comes from a wallpaper basename or the literal
    # "pywal" (see the case above), never arbitrary/untrusted input.
    for addr in $XDG_RUNTIME_DIR/nvim.*; do
        nvim --server "$addr" --remote-send \
            "<Esc>:lua require('theme').apply('${NVIM_THEME}')<CR>" &
    done

    # waybar's style-reload nudge used to live here; waybar was uninstalled
    # 2026-09-01 (replaced by the quickshell bar, which recolors live from
    # ~/.cache/wal/colors.json with no restart).
    # Re-source the generated tmux colours on every running server, so open
    # sessions recolour without a restart. `-q` and `|| true`: there is
    # usually no tmux server at all.
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        tmux source-file ~/.cache/wal/colors-tmux.conf >/dev/null 2>&1 || true
    fi

    # kitty reloads its config on SIGUSR1; without this an open kitty keeps
    # the old palette even though colors-kitty.conf was regenerated.
    pkill -USR1 -x kitty >/dev/null 2>&1 || true

    # NOT `touch ~/.config/ghostty/config`: that ran on every wallpaper
    # switch and never did anything. `man ghostty` says so outright —
    # Ghostty has no config-file watcher at all ("Ghostty isn't capable of
    # this yet"); reload only happens via the app menu, its reload_config
    # keybind, or a full restart. Drive the same action it exposes over
    # D-Bus instead (`gdbus introspect ... com.mitchellh.ghostty` lists it
    # under org.gtk.Actions). Best-effort: harmless if ghostty isn't
    # running or D-Bus is unavailable.
    gdbus call --session --dest com.mitchellh.ghostty \
        --object-path /com/mitchellh/ghostty \
        --method org.gtk.Actions.Activate reload-config '[]' '{}' \
        >/dev/null 2>&1 || true

    # No mako restart needed anymore: quickshell's notification daemon
    # (configs/quickshell/plugins/notifications/) reads colors from
    # Commons/Color.qml, which watches ~/.cache/wal/colors.json directly
    # and recolors live -- no process restart required (see TODO.md).
}

# A dmenu-style picker is plain text only (no per-entry icon/image support)
# so the interactive picker below uses
# fzf's preview pane + chafa instead, same approach Omarchy's image-picker
# takes at the thumbnail-generation layer (content-hash-cached JPEG via
# vipsthumbnail) minus its QML carousel, which this repo doesn't run yet.
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

    # Non-interactive surface for the native picker
    # (quickshell plugins/image-picker/). Kept ahead of the fzf path so the
    # panel never has to know about fzf.
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

    # select wallpaper interactively — fzf preview pane renders a cached
    # thumbnail via chafa (real image, not a text list)
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

    # A `sleep 30` used to sit here, waiting out awww's transition. The QML
    # crossfade is driven by the shell's own animation clock and needs no
    # help from this script.
    exit 0
}

main "$@"
