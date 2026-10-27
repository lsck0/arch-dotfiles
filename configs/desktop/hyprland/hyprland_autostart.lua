hl.on("hyprland.start", function()
    -- the hl.env scales too, so quickshell.service and every app it launches see what the compositor's children see
    hl.exec_cmd("uwsm finalize GDK_SCALE")

    -- quickshell's unit waits for the finalize above
    hl.exec_cmd("systemctl --user start quickshell.service")
    hl.exec_cmd("uwsm app -s s -- /usr/lib/polkit-kde-authentication-agent-1")
    -- a copy outlives its app; Qt image copies (they offer image/jxr, whose encoder segfaults) are left alone
    hl.exec_cmd(
        "uwsm app -s b -- wl-clip-persist --clipboard regular -f '^(text/.*|application/.*|[^/]*|image/(png|jpeg|gif|webp|bmp|tiff|avif|svg\\+xml))$'"
    )

    -- the shell expands $DOTFILES (an unset getenv would abort this hook); plugins.nu builds and loads the plugins
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/hyprland/plugins.nu")
    hl.exec_cmd("uwsm app -s b -- $DOTFILES/configs/desktop/shimoji/packs.nu")
    -- a session started docked with the lid already closed
    hl.exec_cmd("$DOTFILES/configs/desktop/hyprland/lid.nu")

    hl.exec_cmd("xhost +SI:localuser:root")
    local backlight = require("platform").kbd_backlight
    if backlight then
        hl.exec_cmd("brightnessctl --device=" .. backlight .. " set 2")
    end
end)
